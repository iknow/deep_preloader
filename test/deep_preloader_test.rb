require 'test_helper'
require 'temp_table_test_case'

ActiveRecord::Base.establish_connection adapter: "sqlite3", database: ":memory:"

# Set up transactional tests
class ActiveSupport::TestCase
  include ActiveRecord::TestFixtures
end

class DeepPreloaderTest < ActiveSupport::TestCase
  include TemporaryTableTestCase

  def test_that_it_has_a_version_number
    refute_nil ::DeepPreloader::VERSION
  end

  def test_parse_hash_spec
    spec          = { a: [:b, { c: :d, e: nil }]}
    parsed_spec   = DeepPreloader::Spec.parse(spec)
    expected_spec = DeepPreloader::Spec.new(a: DeepPreloader::Spec.new(b: nil, c: DeepPreloader::Spec.new(d: nil), e: nil))

    assert_equal(expected_spec, parsed_spec)
  end

  def test_parse_polymorphic_hash_spec
    create_test_model(:model, ->(t){}){}

    parsed_spec   = DeepPreloader::Spec.parse(a: DeepPreloader::PolymorphicSpec.parse(Model => { b: :c }))

    expected_spec = DeepPreloader::Spec.new(a: DeepPreloader::PolymorphicSpec.new(Model => DeepPreloader::Spec.new(b: DeepPreloader::Spec.new(c: nil))))

    assert_equal(expected_spec, parsed_spec)
  end

  def test_preload_belongs_to
    create_test_model(:parent, ->(t){ t.references :child }) do
      belongs_to :child, inverse_of: :parent
    end
    create_test_model(:child, ->(t){ }) do
      has_one :parent, inverse_of: :child
    end

    c = Child.create!
    p = Parent.create!(child: c)
    p.reload

    refute(p.association(:child).loaded?)
    DeepPreloader.preload(p, :child)
    assert(p.association(:child).loaded?)
    assert_equal(c, p.association(:child).target)
  end

  def test_preload_has_one
    create_test_model(:parent, ->(t){ }) do
      has_one :child, inverse_of: :parent
    end
    create_test_model(:child, ->(t){ t.references :parent }) do
      belongs_to :parent, inverse_of: :child
    end

    p = Parent.create!
    c = Child.create!(parent: p)
    p.reload

    refute(p.association(:child).loaded?)
    DeepPreloader.preload(p, :child)
    assert(p.association(:child).loaded?)
    assert_equal(c, p.association(:child).target)
  end

  def test_preload_has_many
    create_test_model(:parent, ->(t){ }) do
      has_many :children, inverse_of: :parent
    end
    create_test_model(:child, ->(t){ t.references :parent }) do
      belongs_to :parent
    end

    p = Parent.create!
    cs = (1..3).map { Child.create(parent: p) }
    p.reload

    refute(p.association(:children).loaded?)
    DeepPreloader.preload(p, :children)
    assert(p.association(:children).loaded?)
    assert_equal(cs.sort, p.association(:children).target.sort)
  end

  def test_preload_polymorphic
    create_test_model(:parent, ->(t){ t.references :child; t.string :child_type }) do
      belongs_to :child, polymorphic: true
    end
    create_test_model(:child1, ->(t){}) do
      has_one :parent, as: :child
    end
    create_test_model(:child2, ->(t){}) do
      has_one :parent, as: :child
    end

    p1 = Parent.create(child: Child1.new)
    p2 = Parent.create(child: Child2.new)
    p1.reload; p2.reload

    [p1, p2].each do |p|
      refute(p.association(:child).loaded?)
      DeepPreloader.preload(p, :child)
      assert(p.association(:child).loaded?)
    end

    assert(p1.association(:child).target.is_a?(Child1))
    assert(p2.association(:child).target.is_a?(Child2))
  end

  def test_recursive_preload_polymorphic
     create_test_model(:parent, ->(t){ t.references :child; t.string :child_type }) do
      belongs_to :child, polymorphic: true
    end
    create_test_model(:child1, ->(t){ t.references :child2 }) do
      has_one :parent, as: :child
      belongs_to :child2
    end
    create_test_model(:child2, ->(t){ t.references :child1 }) do
      has_one :parent, as: :child
      belongs_to :child1
    end

    p1 = Parent.create!(child: Child1.new)
    p2 = Parent.create!(child: Child2.new(child1: p1.child))
    p1.child.update_attribute(:child2_id, p2.child.id)
    p1.reload; p2.reload

    DeepPreloader.preload([p1, p2],
                          DeepPreloader::Spec.new(child: DeepPreloader::PolymorphicSpec.new("Child1" => DeepPreloader::Spec.new(child2: nil),
                                                                                            "Child2" => DeepPreloader::Spec.new(child1: nil))))

    assert(p1.child.association(:child2).loaded?)
    assert_equal(p2.child, p1.child.association(:child2).target)

    assert(p2.child.association(:child1).loaded?)
    assert_equal(p1.child, p2.child.association(:child1).target)
  end

  def test_already_loaded_single
    create_test_model(:parent, ->(t){ t.references :child }) do
      belongs_to :child, inverse_of: :parent
    end
    create_test_model(:child, ->(t){ }) do
      has_one :parent, inverse_of: :child
    end

    p1, p2 = (1..2).map { Parent.create!(child: Child.new) }
    p3, p4 = (1..2).map { Parent.create!(child: nil) }
    c1_oid = p1.child.object_id
    c2_oid = p2.child.object_id
    p2.reload
    p4.reload

    [p1, p3].each do |p|
      assert_predicate(p.association(:child), :loaded?)
    end
    [p2, p4].each do |p|
      refute_predicate(p.association(:child), :loaded?)
    end

    DeepPreloader.preload([p1, p2, p3, p4], :child)

    [p1, p2, p3, p4].each do |p|
      assert_predicate(p.association(:child), :loaded?)
    end

    assert_equal(c1_oid, p1.association(:child).target.object_id)
    refute_equal(c2_oid, p2.association(:child).target.object_id)
    assert_nil(p3.association(:child).target)
    assert_nil(p4.association(:child).target)
  end

  def test_already_loaded_multiple
    create_test_model(:parent, ->(t){ }) do
      has_many :children, inverse_of: :parent
    end
    create_test_model(:child, ->(t){ t.references :parent }) do
      belongs_to :parent
    end

    p1, p2 = (1..2).map { Parent.create!(children: [Child.new]) }
    c1_oid = p1.children.first.object_id
    c2_oid = p2.children.first.object_id
    p2.reload

    assert(p1.association(:children).loaded?)
    refute(p2.association(:children).loaded?)

    DeepPreloader.preload([p1, p2], :children)
    assert(p1.association(:children).loaded?)
    assert_equal(c1_oid, p1.association(:children).target.first.object_id)
    refute_equal(c2_oid, p2.association(:children).target.first.object_id)
  end
end
