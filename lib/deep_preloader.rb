require "deep_preloader/version"
require "deep_preloader/spec"
require "active_record"

module DeepPreloader
  def self.preload(models, hash_spec)
    spec = Spec.parse_hash_spec(hash_spec)
    spec.preload(models)
  end

  # Through associations associations not supported for now
  def self.preload_association(models, association_reflection, child_spec)
    unless association_reflection.is_a?(ActiveRecord::Reflection::AssociationReflection)
      raise "Unsupported reflection type #{association_reflection.class.name}"
    end

    unless association_reflection.conditions.flatten.blank?
      raise ArgumentError.new("Preloading conditional associations not supported: #{association_reflection.name}")
    end

    unless association_reflection.scope.blank?
      raise ArgumentError.new("Preloading scoped associations not supported: #{association_reflection.name}")
    end

    if association_reflection.polymorphic?
      preload_polymorphic_association(models, association_reflection, child_spec)
    else
      scope = association_reflection.klass.unscoped
      if association_reflection.options[:as]
        scope = scope.where(association_reflection.type => klass.base_class.sti_name)
      end
      preload_direct_association(models, association_reflection, scope, child_spec)
    end
  end

  def self.preload_direct_association(models, association_reflection, scope, child_spec)
    case association_reflection.macro
    when :belongs_to
      preload_belongs_to_association(models, association_reflection, scope, child_spec)
    when :has_one
      preload_has_one_association(models, association_reflection, scope, child_spec)
    when :has_many
      preload_has_many_association(models, association_reflection, scope, child_spec)
    else
      raise "Unsupported association type #{reflection_type}"
    end
  end

  # belongs_to: polymorphic: group the models by the foreign_type, look up each grouping as normal.
  def self.preload_polymorphic_association(models, association_reflection, child_spec)
    models_by_klass_name = models.group_by { |m| m.read_attribute(association_reflection.foreign_type) }
    models_by_klass_name.each do |klass_name, klass_models|
      scope = klass_name.constantize.unscoped
      preload_belongs_to_association(klass_models, association_reflection, scope, child_spec)
    end
  end

  def self.preload_belongs_to_association(models, association_reflection, scope, child_spec)
    assoc = association_reflection.name
    fk = association_reflection.foreign_key

    fk_ids = models.map { |m| m.read_attribute(fk) }.uniq
    children = scope.where(id: fk_ids).to_a

    child_spec.preload(children) if child_spec.present?

    children_by_id = children.index_by(&:id)

    models.each do |m|
      m.association(assoc).target = children_by_id[m.read_attribute(fk)]
    end
  end

  def self.preload_has_one_association(models, association_reflection, scope, child_spec)
    assoc = association_reflection.name
    fk = association_reflection.foreign_key

    children = scope.where(fk => models.map(&:id)).uniq.to_a

    child_spec.preload(children) if child_spec.present?

    children_by_fk = children.index_by { |rel| rel.read_attribute(fk) }

    models.each do |m|
      m.association(assoc).target = children_by_fk[m.id]
    end
  end

  def self.preload_has_many_association(models, association_reflection, scope, child_spec)
    assoc = association_reflection.name
    fk = association_reflection.foreign_key

    children = scope.where(fk => models.map(&:id)).to_a

    child_spec.preload(children) if child_spec.present?

    children_by_fk = children.group_by { |rel| rel.read_attribute(fk) }

    models.each do |m|
      m.association(assoc).target = children_by_fk.fetch(m.id, [])
    end
  end

end
