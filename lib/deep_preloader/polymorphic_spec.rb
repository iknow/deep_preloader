require 'deep_preloader/abstract_spec'

class DeepPreloader::PolymorphicSpec < DeepPreloader::AbstractSpec
  attr_reader :specs_by_type

  def self.parse(data)
    if data.is_a?(Hash)
      specs = data.each_with_object({}) do |(k, v), h|
        unless k < ActiveRecord::Base
          raise ArgumentError.new("Invalid polymorphic spec: '#{k.inspect}' is not a model class")
        end
        h[k] = DeepPreloader::Spec.parse(v)
      end
      self.new(specs)
    else
      raise ArgumentError.new("Invalid polymorphic spec: '#{data.inspect}' is not a hash")
    end
  end

  def initialize(specs_by_type = {})
    @specs_by_type = specs_by_type
  end

  def for_type(clazz)
    specs_by_type[clazz.name]
  end

  def preload(models)
    return if models.blank?

    models_by_type = models.group_by(&:class)
    models_by_type.each do |type, type_models|
      type_spec = for_type(type)
      next unless type_spec
      type_spec.preload(type_models)
    end
  end

  def merge!(other)
    case other
    when nil
      return
    when DeepPreloader::PolymorphicSpec
      other.specs_by_type.each do |k, v|
        if specs_by_type[k]
          specs_by_type[k].merge!(v)
        else
          specs_by_type[k] = v
        end
      end
    else
      raise ArgumentError.new("Cannot merge #{other.class.name} into #{self.inspect}")
    end
    self
  end

  def hash
    [self.class, self.specs_by_type].hash
  end

  def ==(other)
    self.class == other.class && self.specs_by_type == other.specs_by_type
  end

  alias eql? ==

  def inspect
    "PolySpec#{specs_by_type.inspect}"
  end
end
