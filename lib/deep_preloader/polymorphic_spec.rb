require 'deep_preloader/abstract_spec'

class DeepPreloader::PolymorphicSpec < DeepPreloader::AbstractSpec
  attr_reader :specs_by_type

  def self.parse(data)
    if data.is_a?(Hash)
      specs = data.each_with_object({}) do |(k, v), h|
        h[k.to_s] = DeepPreloader::Spec.parse(v)
      end
      self.new(specs)
    else
      raise ArgumentError.new("Invalid polymorphic spec: '#{data.inspect}' is not a hash")
    end
  end

  def initialize(specs_by_type = {})
    @specs_by_type = specs_by_type
  end

  def polymorphic?
    true
  end

  def for_type(clazz)
    specs_by_type[clazz.name]
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
          specs_by_type[k] = v.deep_dup
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

  def deep_dup
    self.class.new(specs_by_type.deep_dup)
  end

  def inspect
    "PolySpec#{specs_by_type.inspect}"
  end
end
