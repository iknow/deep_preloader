require "deep_preloader/version"
require "deep_preloader/spec"
require "deep_preloader/polymorphic_spec"
require "active_record"

DEBUG = ENV['DEBUG'].present?

class DeepPreloader
  def self.preload(models, spec, lock: nil)
    return if spec.nil? || models.blank?

    worker = PreloadWorker.new(lock: lock)
    spec = Spec.parse(spec) unless spec.is_a?(AbstractSpec)

    models_by_class = Array.wrap(models).group_by(&:class)

    case spec
    when Spec
      unless models_by_class.size == 1
        raise ArgumentError.new("Provided multiple model types to non-polymorphic preload spec")
      end

      model_class, models = models_by_class.first
      worker.add_associations_from_spec(models, model_class, spec)
    when PolymorphicSpec
      models_by_class.each do |model_class, models|
        model_spec = spec.for_type(model_class)
        next unless model_spec
        worker.add_associations_from_spec(models, model_class, model_spec)
      end
    end

    worker.run!
    models
  end

  class PreloadWorker
    SENTINEL = Object.new

    def initialize(lock:)
      @lock     = lock
      @worklist = {}
      @known    = {}
    end

    def add_associations_from_spec(models, model_class, spec)
      spec.association_specs.each do |association_name, child_spec|
        association_reflection = model_class.reflect_on_association(association_name)
        if association_reflection.nil?
          raise ArgumentError.new("Preloading error: couldn't find association #{association_name} on model class #{model_class.name}")
        end

        if association_reflection.polymorphic?
          add_polymorphic_association(models, association_reflection, child_spec)
        else
          add_association(models, association_reflection, child_spec)
        end
      end
    end

    def run!
      while(@worklist.present?)
        context, entries = @worklist.shift
        ActiveRecord::Base.logger.debug("Preloading children in context #{context}") if DEBUG

        # Because context shares the key, if any entries are `belongs_to` they
        # all are. (This wouldn't be the case if A belongs_to B via B's foreign
        # key to C, but that's just wrong. Nonetheless we probably want to put
        # the association direction into the context to avoid this.)

        ### ### DO NOT MERGE THIS ### ###

        belongs_to = entries.first.belongs_to?

        known_children = (@known[context] ||= {})

        unloaded = {}

        entries.each do |entry|
          k = entry.key
          if !k
            # entry has no children: mark it as loaded.
            entry.childless!
          elsif entry.loaded?
            # when we have pre-loaded pointed-to children, record them for re-use
            if belongs_to
              known_children[k] ||= entry.children
            end
          else
            (unloaded[k] ||= []) << entry
          end
        end

        ActiveRecord::Base.logger.debug("Need to load children for following keys: #{unloaded.keys}") if DEBUG

        # Reuse any known entities that we point to
        if belongs_to
          unloaded.delete_if do |key, key_entries|
            if (children = known_children.fetch(key, SENTINEL)) != SENTINEL
              key_entries.each do |entry|
                entry.children = children
              end
              true
            end
          end
        end

        # Fetch remaining from database
        if unloaded.present?
          found_children = context.load_children(unloaded.keys, lock: @lock)
          ActiveRecord::Base.logger.debug("fetched children for keys #{found_children.keys}") if DEBUG

          unloaded.each do |key, key_entries|
            if (children = found_children.fetch(key, SENTINEL)) != SENTINEL
              key_entries.each do |entry|
                entry.children = children
              end
            else
              key_entries.each(&:childless!)
            end
          end
        end

        entries.each do |entry|
          children = entry.children
          child_spec = entry.child_spec
          next unless child_spec && children.present?
          child_class = children.first.class # children of a given parent are all of the same type
          add_associations_from_spec(children, child_class, child_spec)
        end

      end

    end

    private

    def add_polymorphic_association(models, association_reflection, polymorphic_child_spec)
      assoc_name = association_reflection.name

      # If a model belongs_to a polymorphic child, we know what type it is.
      # Group models by the type of their associated child and add each
      # separately.
      models_by_child_class = models.group_by { |m| m.association(assoc_name).klass }

      # For models with no child there's nothing to preload, but we still need
      # to set the association target. Since we can't infer a class for
      # `add_association`, set it up here.
      models_by_child_class.delete(nil)&.each do |model|
        model.association(assoc_name).loaded!
      end

      models_by_child_class.each do |child_class, child_class_models|
        child_preload_spec = polymorphic_child_spec&.for_type(child_class)
        add_association(child_class_models, association_reflection, child_preload_spec, type: child_class)
      end
    end

    def add_association(models, association_reflection, child_preload_spec, type: association_reflection.klass)
      key_col           = child_key_column(association_reflection)
      child_constraints = child_constraints(association_reflection)

      context = WorklistContext.new(type, key_col, child_constraints)
      models.each do |model|
        entry = WorklistEntry.new(model, association_reflection, child_preload_spec)
        worklist_add(context, entry)
      end
    end

    def worklist_add(key, entry)
      (@worklist[key] ||= []) << entry
    end

    def child_constraints(association_reflection)
      constraints = []
      if association_reflection.options[:as]
        # each parent model is pointed to from a child type that could also belong to other types of parent. Constrain the search to this parent.
        constraints << [association_reflection.type, association_reflection.active_record.base_class.sti_name]
      end

      unless association_reflection.constraints.blank?
        raise ArgumentError.new("Preloading conditional associations not supported: #{association_reflection.name}")
      end

      unless association_reflection.scope.blank?
        raise ArgumentError.new("Preloading scoped associations not supported: #{association_reflection.name}")
      end

      constraints
    end

    def child_key_column(association_reflection)
      case association_reflection.macro
      when :belongs_to
        association_reflection.active_record_primary_key
      when :has_one, :has_many
        association_reflection.foreign_key
      else
        raise "Unsupported association type #{association_reflection.macro}"
      end
    end
  end

  # entries need to be grouped by:
  # child_type - look up in same table
  # child_key  - compare the same keys
  # child_search_constraints - where constraints on child lookup such as polymorphic type or association scope.
  WorklistContext = Struct.new(:child_type, :child_key_column, :child_constraints) do
    def load_children(keys, lock: nil)
      scope = child_constraints.inject(child_type.unscoped) do |sc, (col, val)|
        sc.where(col => val)
      end

      if lock
        scope = scope.lock(lock)
      end

      scope.where(child_key_column => keys).group_by { |c| c.read_attribute(child_key_column) }
    end
  end

  class WorklistEntry
    attr_reader :model, :association_reflection, :child_spec

    def initialize(model, association_reflection, child_spec)
      @model = model
      @association_reflection = association_reflection
      @association = model.association(association_name)
      @child_spec = child_spec
      @association_macro = association_reflection.macro
    end

    def association_name
      @association_reflection.name
    end

    def association_macro
      @association_reflection.macro
    end

    def loaded?
      @association.loaded?
    end

    def belongs_to?
      @association_macro == :belongs_to
    end

    def collection?
      @association_macro == :has_many
    end

    def key
      model.read_attribute(parent_key_column)
    end

    # Conceal the difference between singular and collection associations so
    # that `load_children` can always `group_by` the key
    def children
      target = @association.target

      if collection?
        target
      elsif target
        [target]
      else
        []
      end
    end

    def children=(targets)
      if collection?
        target = targets
      else
        if targets.size > 1
          raise RuntimeError.new("Internal preloader error: attempted to attach multiple children to a singular association")
        end
        target = targets.first
      end

      ActiveRecord::Base.logger.debug("attaching children to #{model.inspect}.#{association_name}: #{targets}") if DEBUG

      # @association.loaded!
      @association.target = target
      targets.each { |t| @association.set_inverse_instance(t) }
      targets
    end

    def childless!
      ActiveRecord::Base.logger.debug("marking childless as loaded: #{model.inspect}.#{association_name}") if DEBUG
      @association.target = (collection? ? [] : nil)
    end

    def parent_key_column
      case @association_macro
      when :belongs_to
        @association_reflection.foreign_key
      when :has_one, :has_many
        @association_reflection.active_record_primary_key
      else
        raise "Unsupported association type #{@association_macro}"
      end
    end
  end

end
