class AddSessionsTable < ActiveRecord::Migration
  def self.up
    create_table :sessions do |t|
      t.string :session_id, limit: 255, null: false
      t.text :data
      t.timestamps null: true
    end

    add_index :sessions, :session_id
    add_index :sessions, :updated_at
  end

  def self.down
    drop_table :sessions
  end
end
