require 'deep_preloader/abstract_spec'

class DeepPreloader::Spec < DeepPreloader::AbstractSpec
  attr_reader :association_specs

  def self.parse(data)
    case data
    when Array
      data.inject(self.new) do |acc, v|
        acc.merge!(parse(v))
      end
    when Hash
      assoc_specs = data.each_with_object({}) do |(k, v), h|
        h[k.to_sym] = parse(v)
      end
      self.new(assoc_specs)
    when String, Symbol
      self.new({ data.to_sym => nil })
    when DeepPreloader::AbstractSpec
      data
    when nil
      nil
    else
      raise ArgumentError.new("Cannot parse invalid hash preload spec: #{hash.inspect}")
    end
  end

  def initialize(association_specs = {})
    @association_specs = association_specs
  end

  def preload(models)
    return if models.blank?

    model_class = models.first.class
    unless models.all? { |m| m.class == model_class }
      raise ArgumentError.new("Cannot preload mixed type models")
    end

    association_specs.each do |association_name, child_spec|
      association_reflection = model_class.reflect_on_association(association_name)
      DeepPreloader.preload_association(models, association_reflection, child_spec)
    end
  end

  def merge!(other)
    case other
    when nil
      return
    when DeepPreloader::Spec
      other.association_specs.each do |k, v|
        if association_specs[k]
          association_specs[k].merge!(v)
        else
          association_specs[k] = v
        end
      end
    else
      raise ArgumentError.new("Cannot merge #{other.class.name} into #{self.inspect}")
    end
    self
  end

  def hash
    [self.class, self.association_specs].hash
  end

  def ==(other)
    self.class == other.class && self.association_specs == other.association_specs
  end

  alias eql? ==

  def inspect
    "Spec#{association_specs.inspect}"
  end
end
