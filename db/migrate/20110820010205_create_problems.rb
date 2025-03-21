class CreateProblems < ActiveRecord::Migration
  def self.up
    create_table :problems do |t|
      t.string :title, limit: 255
      t.text :statement
      t.string :input, limit: 255
      t.string :output, limit: 255
      t.integer :memory_limit
      t.decimal :time_limit
      t.integer :user_id

      t.timestamps null: true
    end
  end

  def self.down
    drop_table :problems
  end
end
