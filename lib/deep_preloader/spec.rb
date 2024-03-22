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
        h[k.to_s] = parse(v)
      end
      self.new(assoc_specs)
    when String, Symbol
      self.new({ data.to_s => nil })
    when DeepPreloader::AbstractSpec
      data
    when nil
      nil
    else
      raise ArgumentError.new("Cannot parse invalid hash preload spec: #{hash.inspect}")
    end
  end

  def initialize(association_specs = {})
    @association_specs = association_specs.transform_keys(&:to_s)
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
          association_specs[k] = v.deep_dup
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

  def deep_dup
    self.class.new(association_specs.deep_dup)
  end

  def inspect
    "Spec#{association_specs.inspect}"
  end
end
