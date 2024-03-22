# frozen_string_literal: true

RSpec.describe DeepPreloader do
  RSpec::Matchers.define :have_loaded do |association_name|
    match do |actual|
      assoc = actual.association(association_name)
      assoc.loaded? && @comparator.(@target, assoc.target)
    end

    chain :as do |target|
      @target = target
      @comparator = method(:values_match?)
    end

    chain :as_object do |target|
      @target = target
      @comparator = ->(a, b) { a.equal?(b) }
    end

    failure_message do |actual|
      assoc = actual.association(association_name)
      if assoc.loaded?
        "expected #{actual.inspect} to have loaded #{association_name} as #{@target.inspect}, but was #{assoc.target.inspect}"
      else
        "expected #{actual.inspect} to have loaded #{association_name}"
      end
    end
  end

  it 'can parse a hash spec' do
    spec          = { a: [:b, { c: :d, e: nil }] }
    expected_spec = DeepPreloader::Spec.new(a: DeepPreloader::Spec.new(b: nil, c: DeepPreloader::Spec.new(d: nil), e: nil))

    expect(DeepPreloader::Spec.parse(spec)).to eq(expected_spec)
  end

  it 'can merge specs' do
    a = DeepPreloader::Spec.parse(a: :b)
    b = DeepPreloader::Spec.parse(a: :c)
    result = DeepPreloader::Spec.new.merge!(a).merge!(b)

    # The result should contain each of the merged specs and the merged specs
    # themselves should not be altered
    expect(result).to eq(DeepPreloader::Spec.parse(a: [:b, :c]))
    expect(a).to eq(DeepPreloader::Spec.parse(a: :b))
    expect(b).to eq(DeepPreloader::Spec.parse(a: :c))
  end

  context 'with a test model' do
    with_temporary_table(:model)

    it 'can parse a polymorphic hash spec' do
      parsed_spec   = DeepPreloader::Spec.parse(a: DeepPreloader::PolymorphicSpec.parse('Model' => { b: :c }))
      expected_spec = DeepPreloader::Spec.new(a: DeepPreloader::PolymorphicSpec.new('Model' => DeepPreloader::Spec.new(b: DeepPreloader::Spec.new(c: nil))))

      expect(parsed_spec).to eq(expected_spec)
    end
  end

  context 'with a one-to-one relationship' do
    with_temporary_table(:parent, ->(t) { t.references :child }) do
      belongs_to :child, inverse_of: :parent
    end

    with_temporary_table(:child) do
      has_one :parent, inverse_of: :child
    end

    let(:child) { Child.create! }
    let(:parent) { Parent.create!(child: child) }
    # Reload to ensure that the associations that were set on create! are cleared.
    before(:each) do
      parent.reload
      child.reload
    end

    context 'in the belongs_to direction' do
      let(:childless) { Parent.create! }

      it 'is not already loaded' do
        expect(parent.association(:child)).to_not be_loaded
        expect(child.association(:parent)).to_not be_loaded
      end

      it 'loads the child' do
        DeepPreloader.preload(parent, :child)
        expect(parent).to have_loaded(:child).as(child)
      end

      it 'sets up the inverse relationship' do
        DeepPreloader.preload(parent, :child)
        expect(parent.child).to have_loaded(:parent).as(parent)
      end

      it 'satisfies a childless parent' do
        DeepPreloader.preload(childless, :child)
        expect(childless).to have_loaded(:child).as(nil)
      end

      it 'loads more than one entity' do
        DeepPreloader.preload([parent, childless], :child)
        [[parent, child], [childless, nil]].each do |p, c|
          expect(p).to have_loaded(:child).as(c)
        end
      end

      it 'uses preloaded children from other parents before hitting the database' do
        loaded_parent = Parent.create!(child: child)
        expect(loaded_parent).to have_loaded(:child).as_object(child)

        DeepPreloader.preload([parent, loaded_parent], :child)
        [parent, loaded_parent].each do |p|
          expect(p).to have_loaded(:child).as_object(child)
        end
      end

      it 'supports locking' do
        DeepPreloader.preload(parent, :child, lock: 'FOR SHARE')
        # No real way to test this with sqlite: AR drops the lock clause.
      end
    end

    context 'in the has_one direction' do
      let(:parentless) { Child.create! }

      it 'loads the parent' do
        DeepPreloader.preload(child, :parent)
        expect(child).to have_loaded(:parent).as(parent)
      end

      it 'sets up the inverse relationship' do
        DeepPreloader.preload(child, :parent)
        expect(child.parent).to have_loaded(:child).as(child)
      end

      it 'satisfies a parentless child' do
        DeepPreloader.preload(parentless, :parent)
        expect(parentless).to have_loaded(:parent).as(nil)
      end

      it 'loads more than one entity' do
        DeepPreloader.preload([child, parentless], :parent)
        [[child, parent], [parentless, nil]].each do |c, p|
          expect(c).to have_loaded(:parent).as(p)
        end
      end

      it 'handles a preloaded child' do
        expected_parent = child.parent # force load

        DeepPreloader.preload(child, :parent)
        expect(child).to have_loaded(:parent).as_object(expected_parent)
      end
    end
  end

  context 'with multiple belongs_to relationships' do
    with_temporary_table(:child)

    with_temporary_table(:parent1, ->(t) { t.references :a_child; t.references :b_child }) do
      belongs_to :a_child, class_name: Child.name
      belongs_to :b_child, class_name: Child.name
    end

    with_temporary_table(:parent2, ->(t) { t.references :child }) do
      belongs_to :child
    end

    let(:p1) { Parent1.create!(a_child: c1, b_child: c2) }
    let(:p2) { Parent2.create!(child: c3) }

    before(:each) do
      [p1, p2].each(&:reload)
      [c1, c2, c3].each(&:reload)
    end

    context 'with distinct children' do
      let(:c1) { Child.create! }
      let(:c2) { Child.create! }
      let(:c3) { Child.create! }

      it 'loads multiple relationships at once' do
        spec = DeepPreloader::PolymorphicSpec.parse(Parent1.name => [:a_child, :b_child], Parent2.name => :child)
        DeepPreloader.preload([p1, p2], spec)
        expect(p1).to have_loaded(:a_child).as(c1)
        expect(p1).to have_loaded(:b_child).as(c2)
        expect(p2).to have_loaded(:child).as(c3)
      end
    end

    context 'with a diamond' do
      let(:c1) { Child.create! }
      let(:c2) { c1 }
      let(:c3) { c1 }

      it 'loads the same child for all three' do
        spec = DeepPreloader::PolymorphicSpec.parse(Parent1.name => [:a_child, :b_child], Parent2.name => :child)
        DeepPreloader.preload([p1, p2], spec)
        expect(p1).to have_loaded(:a_child).as(c1)
        c = p1.a_child
        expect(p1).to have_loaded(:b_child).as_object(c)
        expect(p2).to have_loaded(:child).as_object(c)
      end
    end
  end

  context 'with a has_many relationship' do
    with_temporary_table(:parent) do
      has_many :children, inverse_of: :parent
    end

    with_temporary_table(:child, ->(t) { t.references :parent }) do
      belongs_to :parent, inverse_of: :children
    end

    let(:children) { 3.times.map { Child.create! } }
    let(:parent) { Parent.create!(children: children).tap(&:reload) }
    let(:childless) { Parent.create!.tap(&:reload) }

    before(:each) do
      parent.reload
      childless.reload
      children.each(&:reload)
    end

    it 'loads the child' do
      DeepPreloader.preload(parent, :children)
      expect(parent).to have_loaded(:children).as(children)
    end

    it 'sets up the inverse relationship' do
      DeepPreloader.preload(parent, :children)
      parent.children.each do |child|
        expect(child).to have_loaded(:parent).as(parent)
      end
    end

    it 'satisfies a childless parent' do
      DeepPreloader.preload(childless, :children)
      expect(childless).to have_loaded(:children).as([])
    end

    it 'handles preloaded children' do
      parent.children # force load
      DeepPreloader.preload(parent, :children)
      expect(parent).to have_loaded(:children).as(children)
    end
  end

  context 'with a has_many STI relationship' do
    with_temporary_table(:parent) do
      has_many :pets, inverse_of: :parent
    end

    with_temporary_table(:pet, ->(t) { t.string :type; t.references :parent; t.references :cat_toy; t.references :dog_toy }) do
      belongs_to :parent, inverse_of: :pets
    end

    with_temporary_table(:cat, superclass: -> { Pet }, create_table: false) do
      belongs_to :cat_toy
    end

    with_temporary_table(:dog, superclass: -> { Pet }, create_table: false) do
      belongs_to :dog_toy
    end

    with_temporary_table(:cat_toy) do
      has_one :cat, inverse_of: :cat_toy
    end

    with_temporary_table(:dog_toy) do
      has_one :dog, inverse_of: :dog_toy
    end

    let(:parent) do
      Parent.create!(pets: pets)
    end

    let(:pets) do
      [Dog.create(dog_toy: DogToy.new), Cat.create(cat_toy: CatToy.new)]
    end

    before(:each) do
      parent.reload
    end

    it 'loads the children' do
      DeepPreloader.preload(parent, :pets)
      expect(parent).to have_loaded(:pets).as(pets)
    end

    it 'loads polymorphically through the children' do
      DeepPreloader.preload(parent, { :pets => DeepPreloader::PolymorphicSpec.parse(Dog.name => :dog_toy, Cat.name => :cat_toy) })
      expect(parent).to have_loaded(:pets).as(pets)
      expect(pets[0]).to have_loaded(:parent).as(parent)
      expect(pets[1]).to have_loaded(:parent).as(parent)

      parent_pets = parent.pets.sort_by(&:id)

      expect(parent_pets[0]).to have_loaded(:dog_toy).as(pets[0].dog_toy)
      expect(parent_pets[1]).to have_loaded(:cat_toy).as(pets[1].cat_toy)

      expect(parent_pets[0].dog_toy).to have_loaded(:dog).as(pets[0])
      expect(parent_pets[1].cat_toy).to have_loaded(:cat).as(pets[1])
    end
  end

  context 'with a polymorphic relationship' do
    with_temporary_table(:parent, ->(t) { t.references :child; t.string :child_type }) do
      belongs_to :child, polymorphic: true, inverse_of: :parent
    end
    with_temporary_table(:child1, ->(t) { t.references :grandchild }) do
      has_one :parent, as: :child
      belongs_to :grandchild, inverse_of: :child2
    end
    with_temporary_table(:child2, ->(t) { t.references :grandchild }) do
      has_one :parent, as: :child
      belongs_to :grandchild, inverse_of: :child2
    end
    with_temporary_table(:grandchild) do
      has_one :child1, inverse_of: :grandchild
      has_one :child2, inverse_of: :grandchild
    end

    let(:c1) { Child1.create! }
    let(:c2) { Child2.create! }
    let(:p1) { Parent.create(child: c1) }
    let(:p2) { Parent.create(child: c2) }

    before(:each) do
      [p1, p2].each(&:reload)
      [c1, c2].each(&:reload)
    end

    it 'loads different child types' do
      DeepPreloader.preload([p1, p2], :child)
      expect(p1).to have_loaded(:child).as(c1)
      expect(p2).to have_loaded(:child).as(c2)
    end

    it 'sets the inverse associations' do
      DeepPreloader.preload([p1, p2], :child)
      expect(p1.child).to have_loaded(:parent).as(p1)
      expect(p2.child).to have_loaded(:parent).as(p2)
    end

    it 'separates parent context when loading backwards' do
      DeepPreloader.preload([c1, c2], DeepPreloader::PolymorphicSpec.parse(Child1.name => :parent, Child2.name => :parent))
      expect(c1).to have_loaded(:parent).as(p1)
      expect(c2).to have_loaded(:parent).as(p2)
    end

    it 'satisfies a childless parent' do
      childless = Parent.create!
      DeepPreloader.preload(childless, :child)
      expect(childless).to have_loaded(:child).as(nil)
    end

    context 'with grandchildren' do
      let(:g1) { Grandchild.create!(child1: c1) }
      let(:g2) { Grandchild.create!(child2: c2) }

      before(:each) do
        [g1, g2].each(&:reload)
        [c1, c2].each(&:reload)
      end

      it 'loads sub-specs through the polymorphic association' do
        DeepPreloader.preload([p1, p2], { :child => DeepPreloader::PolymorphicSpec.parse(Child1.name => :grandchild, Child2.name => :grandchild) })
        expect(p1).to have_loaded(:child).as(c1)
        expect(p2).to have_loaded(:child).as(c2)
        expect(p1.child).to have_loaded(:grandchild).as(g1)
        expect(p2.child).to have_loaded(:grandchild).as(g2)
      end
    end
  end
end
