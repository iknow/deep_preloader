class DeepPreloader::Spec
  def self.parse_hash_spec(spec_data)
    case spec_data
    when Array
      spec = {}
      spec_data.each do |v|
        spec[v.to_sym] = nil
      end
      Spec.new(spec)
    when Hash
      spec = {}
      spec_data.each do |k, v|
        spec[k.to_sym] = parse_hash_spec(v)
      end
      Spec.new(spec)
    when nil
      nil
    else
      Spec.new({ spec_data.to_sym => nil })
    end
  end

  def initialize(association_specs)
    @association_specs = association_specs
  end

  def preload(models)
    model_type = models.first.class
    unless models.all? { |m| m.class == model_type }
      raise ArgumentError.new("Cannot preload mixed type models")
    end

    association_specs.each do |association_name, child_spec|
      association_reflection = model_class.reflect_on_association(association_name)
      DeepPreloader.preload_association(models, association_reflection, child_spec)
    end
  end
end
