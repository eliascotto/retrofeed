class CreateContentErrorGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :content_error_groups do |t|
      t.string :fingerprint, null: false
      t.string :phase, null: false
      t.string :operation, null: false
      t.string :severity, null: false, default: "error"
      t.string :status, null: false, default: "open"

      t.string :subject_type
      t.bigint :subject_id
      t.string :domain
      t.text :url

      t.string :exception_class
      t.text :message, null: false

      t.string :job_class
      t.string :active_job_id
      t.string :queue_name
      t.json :job_arguments
      t.integer :attempt

      t.integer :http_status
      t.string :http_method
      t.string :content_type
      t.json :response_headers

      t.integer :occurrences_count, null: false, default: 1
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false

      t.timestamps
    end

    add_index :content_error_groups, [ :fingerprint, :subject_type, :subject_id, :domain ],
              unique: true,
              name: "index_content_error_groups_on_fingerprint_and_subject"
    add_index :content_error_groups, [ :status, :last_seen_at ]
    add_index :content_error_groups, [ :subject_type, :subject_id, :status, :last_seen_at ],
              name: "index_content_error_groups_on_subject_status_last_seen"
    add_index :content_error_groups, [ :domain, :status, :last_seen_at ],
              name: "index_content_error_groups_on_domain_status_last_seen"
  end
end
