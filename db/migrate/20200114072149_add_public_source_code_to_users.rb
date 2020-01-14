class AddPublicSourceCodeToUsers < ActiveRecord::Migration
  def change
    add_column :users, :public_source_code, :boolean, :default => false
  end
end
