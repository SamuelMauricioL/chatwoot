class AddCachedLabelsList < ActiveRecord::Migration[7.0]
  def change
    add_column :conversations, :cached_label_list, :string
    Conversation.reset_column_information
    # Fix: ActsAsTaggableOn::Taggable::Cache no longer exists in newer gem versions
    # ActsAsTaggableOn::Taggable::Cache.included(Conversation)
  end
end
