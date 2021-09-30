database = Gemika::Database.new
database.connect


database.rewrite_schema! do

  create_table :records do |t|
    t.string :persisted_string
    t.integer :persisted_integer
    t.datetime :persisted_time
    t.date :persisted_date
    t.boolean :persisted_boolean
  end

  create_table :children do |t|
    t.integer :record_id
    t.boolean :nice
  end

  create_table :pictures do |t|
    t.integer :imageable_id
    t.string :imageable_type
  end

  create_table :uuid_records, id: false do |t|
    t.string :id, primary_key: true, limit: 100
    t.string :persisted_string
  end

  create_table :sti_records do |t|
    t.string :persisted_string
    t.string :type
  end

  create_table :other_records do |t|
    t.string :other_string
  end

  create_table :cars do |t|
    t.integer :status
  end

  create_table :wheels do |t|
    t.integer :car_id
  end

  create_table :steering_wheels do |t|
    t.string :car_id
  end
end
