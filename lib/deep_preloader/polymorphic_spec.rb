class DeepPreloader::PolymorphicSpec
  def initialize(specs_by_type)
    @specs_by_type = specs_by_type
  end

  def preload(models)
    models_by_type = models.group_by(&:class)
    models_by_type.each do |type, type_models|
      type_spec = @specs_by_type[type.name.to_sym]
      next unless association.present?
      type_spec.preload(type_models)
    end
  end
end
