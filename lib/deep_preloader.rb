require "deep_preloader/version"
require "deep_preloader/spec"
require "deep_preloader/polymorphic_spec"
require "active_record"

module DeepPreloader
  def self.preload(models, spec)
    return if spec.nil?
    spec = AbstractSpec.parse_hash_spec(spec) unless spec.is_a?(AbstractSpec)
    spec.preload(Array.wrap(models))
  end

  # Through associations associations not supported for now
  def self.preload_association(models, association_reflection, child_preload_spec)
    unless association_reflection.is_a?(ActiveRecord::Reflection::AssociationReflection)
      raise "Unsupported reflection type #{association_reflection.class.name}"
    end

    unless association_reflection.constraints.blank?
      raise ArgumentError.new("Preloading conditional associations not supported: #{association_reflection.name}")
    end

    unless association_reflection.scope.blank?
      raise ArgumentError.new("Preloading scoped associations not supported: #{association_reflection.name}")
    end

    if association_reflection.polymorphic?
      preload_polymorphic_association(models, association_reflection, child_preload_spec)
    else
      scope = association_reflection.klass.unscoped
      if association_reflection.options[:as]
        scope = scope.where(association_reflection.type => association_reflection.active_record.base_class.sti_name)
      end
      if association_reflection.collection?
        preload_multiple_association(models, association_reflection, scope, child_preload_spec)
      else
        preload_single_association(models, association_reflection, scope, child_preload_spec)
      end
    end
  end

  # belongs_to: polymorphic: group the models by the foreign_type, look up each grouping as normal.
  def self.preload_polymorphic_association(models, association_reflection, child_preload_spec)
    assoc_name = association_reflection.name
    models_by_child_class = models.group_by { |m| m.association(assoc_name).klass }
    models_by_child_class.each do |child_class, child_class_models|
      next if child_class.nil?
      child_scope = child_class.unscoped
      child_class_preload_spec = child_preload_spec.try { |s| s.for_type(child_class) }
      preload_single_association(child_class_models, association_reflection, child_scope, child_class_preload_spec)
    end
  end

  def self.preload_single_association(models, association_reflection, child_scope, child_preload_spec)
    assoc_name = association_reflection.name
    case association_reflection.macro
    when :belongs_to
      parent_key = association_reflection.foreign_key
      child_key  = association_reflection.active_record_primary_key
    when :has_one
      parent_key = association_reflection.active_record_primary_key
      child_key  = association_reflection.foreign_key
    else
      raise "Unsupported association type #{reflection_type}"
    end

    # some models may have the association already loaded
    loaded_models, unloaded_models = models.partition { |m| m.association(assoc_name).loaded? }

    loaded_children = loaded_models.map { |m| m.association(assoc_name).target }
    children_by_key = loaded_children.index_by { |c| c.read_attribute(child_key) }

    # Load children necessary to resolve unloaded models
    unloaded_keys = unloaded_models
                    .map { |m| m.read_attribute(parent_key) }
                    .uniq
                    .reject { |k| children_by_key.has_key?(k) }

    unloaded_children = child_scope.where(child_key => unloaded_keys).to_a
    unloaded_children.each do |c|
      children_by_key[c.read_attribute(child_key)] = c
    end

    child_preload_spec.preload(children_by_key.values) if child_preload_spec.present?

    unloaded_models.each do |m|
      target = children_by_key[m.read_attribute(parent_key)]
      association = m.association(association_reflection.name)
      association.target = target
      association.set_inverse_instance(target) if target
    end
  end

  def self.preload_multiple_association(models, association_reflection, child_scope, child_preload_spec)
    assoc_name = association_reflection.name

    unless association_reflection.macro == :has_many
      raise "Unsupported association type #{reflection_type}"
    end

    parent_key = association_reflection.active_record_primary_key
    child_key  = association_reflection.foreign_key

    # some models may have the association already loaded
    loaded_models, unloaded_models = models.partition { |m| m.association(assoc_name).loaded? }
    loaded_children = loaded_models.flat_map { |m| m.association(assoc_name).target }

    # Load children necessary to resolve unloaded models
    unloaded_keys = unloaded_models.map { |m| m.read_attribute(parent_key) }

    unloaded_children = child_scope.where(child_key => unloaded_keys).to_a
    unloaded_children_by_key = unloaded_children.group_by { |c| c.read_attribute(child_key) }

    child_preload_spec.preload(loaded_children + unloaded_children) if child_preload_spec.present?

    unloaded_models.each do |m|
      targets = unloaded_children_by_key.fetch(m.read_attribute(parent_key), [])
      association = m.association(association_reflection.name)
      association.loaded!
      association.target = targets
      targets.each { |target| association.set_inverse_instance(target) }
    end
  end

end
