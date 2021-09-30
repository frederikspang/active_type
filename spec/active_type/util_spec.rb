require 'spec_helper'
require 'pry'
require 'logger'

ActiveRecord::Base.logger = Logger.new(STDOUT)

module UtilSpec

  class BaseRecord < ActiveRecord::Base
    self.table_name = 'records'
  end

  class ExtendedRecord < ActiveType::Record[BaseRecord]

    attribute :virtual_string
    attribute :virtual_string_for_validation
    after_initialize :set_virtual_string
    attr_reader :after_initialize_called

    def set_virtual_string
      @after_initialize_called = true
      self.virtual_string = "persisted_string is #{persisted_string}"
    end

  end

  class Parent < ActiveRecord::Base
    self.table_name = 'sti_records'
  end

  class Child < Parent
  end

  class ChildSibling < Parent
  end

  class ExtendedChild < ActiveType::Record[Child]
  end

  class Car < ActiveRecord::Base
    has_many :wheels, inverse_of: :car #, autosave: false
    has_one :steering_wheel

    def save!
      binding.pry
      super
    end

    def change_status
      self.status = 10
    end
  end

  class Wheel < ActiveRecord::Base
    belongs_to :car, inverse_of: :wheels
    after_save :update_car_status # <= after save, ein wheel ist also schon gespeichert

    private

    def update_car_status
      car.change_status
      puts "<<<< before car.save!"
      # binding.pry
      car.save! #-> das saved auch den Kind-Record
      puts "<<<< after car.save!"
    end

  end

  class SteeringWheel <ActiveRecord::Base
    belongs_to :car
  end

  class ExtendedCar < ActiveType::Record[Car]
  end

  class ExtendedWheel < ActiveType::Record[Wheel]
  end
end

describe ActiveType::Util do
  describe '.cast' do
    describe 'for a relation' do

      it 'casts a scope to a scope of another class' do
        record = UtilSpec::BaseRecord.create!(:persisted_string => 'foo')
        base_scope = UtilSpec::BaseRecord.where(:persisted_string => 'foo')
        casted_scope = ActiveType::Util.cast(base_scope, UtilSpec::ExtendedRecord)
        expect(casted_scope.build).to be_a(UtilSpec::ExtendedRecord)
        found_record = casted_scope.find(record.id)
        expect(found_record.persisted_string).to eq('foo')
        expect(found_record).to be_a(UtilSpec::ExtendedRecord)
      end

      it 'preserves existing scope conditions' do
        match = UtilSpec::BaseRecord.create!(:persisted_string => 'foo')
        no_match = UtilSpec::BaseRecord.create!(:persisted_string => 'bar')
        base_scope = UtilSpec::BaseRecord.where(:persisted_string => 'foo')
        casted_scope = ActiveType::Util.cast(base_scope, UtilSpec::ExtendedRecord)
        casted_match = UtilSpec::ExtendedRecord.find(match.id)
        expect(casted_scope.to_a).to eq([casted_match])
      end

    end

    describe 'for a record type' do

      context 'TODO' do
        it 'works without Active Type' do
          car = UtilSpec::Car.create

          native_wheel = car.wheels.build
          native_wheel.save!
        end

        it 'works with Active Type' do
          car = UtilSpec::Car.create

          new_wheel = car.wheels.build

          casted_new_wheel = ActiveType.cast(new_wheel, UtilSpec::ExtendedWheel)
          puts "<<<< after cast"
          casted_new_wheel.save!
          puts "<<<< after save!"
        end
      end

      it 'casts a base record to an extended record' do
        base_record = UtilSpec::BaseRecord.create!(:persisted_string => 'foo')
        extended_record = ActiveType::Util.cast(base_record, UtilSpec::ExtendedRecord)
        expect(extended_record).to be_a(UtilSpec::ExtendedRecord)
        expect(extended_record).to be_persisted
        expect(extended_record.id).to be_present
        expect(extended_record.id).to eq(base_record.id)
        expect(extended_record.persisted_string).to eq('foo')
      end

      it 'casts an extended record to a base record' do
        extended_record = UtilSpec::ExtendedRecord.create!(:persisted_string => 'foo')
        base_record = ActiveType::Util.cast(extended_record, UtilSpec::BaseRecord)
        expect(base_record).to be_a(UtilSpec::BaseRecord)
        expect(base_record).to be_persisted
        expect(base_record.id).to be_present
        expect(base_record.id).to eq(extended_record.id)
        expect(base_record.persisted_string).to eq('foo')
      end

      it 'calls after_initialize callbacks of the cast target' do
        base_record = UtilSpec::BaseRecord.create!(:persisted_string => 'foo')
        extended_record = ActiveType::Util.cast(base_record, UtilSpec::ExtendedRecord)
        expect(extended_record.after_initialize_called).to eq true
      end

      it 'lets after_initialize callbacks access attributes (bug in ActiveRecord#becomes)' do
        base_record = UtilSpec::BaseRecord.create!(:persisted_string => 'foo')
        extended_record = ActiveType::Util.cast(base_record, UtilSpec::ExtendedRecord)
        expect(extended_record.virtual_string).to eq('persisted_string is foo')
      end

      it 'preserves the #type of an STI record that is casted to an ExtendedRecord' do
        child_record = UtilSpec::Child.create!(:persisted_string => 'foo')
        extended_child_record = ActiveType::Util.cast(child_record, UtilSpec::ExtendedChild)
        expect(extended_child_record).to be_a(UtilSpec::ExtendedChild)
        expect(extended_child_record.type).to eq('UtilSpec::Child')
      end

      it 'changes the #type of an STI record when casted to another type in the hierarchy' do
        child_record = UtilSpec::Child.create!(:persisted_string => 'foo')
        child_sibling_record = ActiveType::Util.cast(child_record, UtilSpec::ChildSibling)
        expect(child_sibling_record).to be_a(UtilSpec::ChildSibling)
        expect(child_sibling_record.type).to eq('UtilSpec::ChildSibling')
      end

      it 'preserves dirty tracking flags' do
        base_record = UtilSpec::BaseRecord.create!(:persisted_string => 'foo')
        expect(base_record.changes).to eq({})
        base_record.persisted_string = 'bar'
        expect(base_record.changes).to eq({ 'persisted_string' => ['foo', 'bar'] })
        extended_record = ActiveType::Util.cast(base_record, UtilSpec::ExtendedRecord)
        expect(extended_record).to be_a(UtilSpec::ExtendedRecord)
        expect(extended_record.changes).to eq(
          'persisted_string' => ['foo', 'bar'],
          'virtual_string' => [nil, 'persisted_string is bar']
        )
      end

      it 'associates the error object correctly with the new type (BUGFIX)' do
        base_record = UtilSpec::BaseRecord.create!(:persisted_string => 'foo')
        extended_record = ActiveType::Util.cast(base_record, UtilSpec::ExtendedRecord)
        expect {
          value = extended_record.virtual_string_for_validation
          extended_record.errors.add(:virtual_string_for_validation, :empty) if value.nil? || value.empty?
        }.not_to raise_error
        expect(extended_record.errors.size).to eq 1
        expect(base_record.errors.size).to eq 0
      end

      it 'keeps the associations when casting a saved record with associations' do
        wheel = UtilSpec::Wheel.create
        steering_wheel = UtilSpec::SteeringWheel.create
        car = UtilSpec::Car.create(steering_wheel: steering_wheel, wheels: [wheel])

        expect(car.wheels.first).to be_present
        expect(car.steering_wheel).to be_present

        extended_car = ActiveType.cast(car, UtilSpec::ExtendedCar)
        expect(extended_car.wheels.first).to be_present
        expect(extended_car.steering_wheel).to be_present
      end

      it 'keeps the associations when casting a unsaved record with associations' do
        wheel = UtilSpec::Wheel.create
        steering_wheel = UtilSpec::SteeringWheel.create
        car = UtilSpec::Car.new(steering_wheel: steering_wheel, wheels: [wheel])

        expect(car.wheels.first).to eq wheel
        expect(car.steering_wheel).to eq steering_wheel

        extended_car = ActiveType.cast(car, UtilSpec::ExtendedCar)
        expect(extended_car.wheels.first).to eq wheel
        expect(extended_car.steering_wheel).to eq steering_wheel
      end
    end

  end

  it "exposes all methods through ActiveType's root namespace" do
    expect(ActiveType).to respond_to(:cast)
  end

end
