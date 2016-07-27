require 'deep_preloader/abstract_spec'

class DeepPreloader::Spec < DeepPreloader::AbstractSpec
  attr_reader :association_specs

  def initialize(association_specs = {})
    @association_specs = association_specs
  end

  def preload(models)
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
end
