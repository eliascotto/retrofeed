class ConvertPrimaryKeysToUuid < ActiveRecord::Migration[8.1]
  # Application tables converted from bigint/integer primary keys to uuid.
  APP_TABLES = %i[
    users websites articles tags lists subscriptions
    article_tags article_versions list_articles user_articles
    email_sends content_error_groups
  ].freeze

  # Foreign keys as [table, column, referenced_table]. All are NOT NULL.
  FOREIGN_KEYS = [
    [ :articles, :website_id, :websites ],
    [ :subscriptions, :user_id, :users ],
    [ :subscriptions, :website_id, :websites ],
    [ :tags, :user_id, :users ],
    [ :lists, :user_id, :users ],
    [ :article_tags, :article_id, :articles ],
    [ :article_tags, :tag_id, :tags ],
    [ :article_versions, :article_id, :articles ],
    [ :list_articles, :list_id, :lists ],
    [ :list_articles, :article_id, :articles ],
    [ :user_articles, :user_id, :users ],
    [ :user_articles, :article_id, :articles ]
  ].freeze

  def up
    enable_extension "pgcrypto" unless extension_enabled?("pgcrypto")

    add_uuid_primary_key_columns
    add_uuid_foreign_key_columns
    convert_polymorphic_columns
    drop_foreign_keys
    promote_primary_keys
    promote_foreign_keys
    recreate_indexes
    readd_foreign_keys
  end

  private
    # Pass 1: add new uuid primary-key columns, populated for existing rows via
    # the per-row default.
    def add_uuid_primary_key_columns
      APP_TABLES.each do |table|
        add_column table, :uuid, :uuid, default: -> { "gen_random_uuid()" }, null: false
      end
    end

    # Pass 2: add sibling uuid foreign-key columns and backfill across the
    # existing integer relationships. Parents already carry their uuid, so the
    # order within this pass does not matter.
    def add_uuid_foreign_key_columns
      FOREIGN_KEYS.each do |table, column, parent|
        add_column table, uuid_column_name(column), :uuid
        execute <<~SQL.squish
          UPDATE #{table} SET #{uuid_column_name(column)} = #{parent}.uuid
          FROM #{parent} WHERE #{table}.#{column} = #{parent}.id
        SQL
      end
    end

    # The two polymorphic columns that reference app records by id.
    def convert_polymorphic_columns
      # content_error_groups.subject -> Article | Website.
      add_column :content_error_groups, :subject_uuid, :uuid
      execute <<~SQL.squish
        UPDATE content_error_groups SET subject_uuid = websites.uuid
        FROM websites WHERE subject_type = 'Website' AND subject_id = websites.id
      SQL
      execute <<~SQL.squish
        UPDATE content_error_groups SET subject_uuid = articles.uuid
        FROM articles WHERE subject_type = 'Article' AND subject_id = articles.id
      SQL

      # Active Storage record_id points at app records (Website favicon, List
      # cover_image), so it must become a string able to hold uuid text.
      add_column :active_storage_attachments, :record_uuid, :string
      execute <<~SQL.squish
        UPDATE active_storage_attachments SET record_uuid = websites.uuid::text
        FROM websites WHERE record_type = 'Website' AND record_id = websites.id
      SQL
      execute <<~SQL.squish
        UPDATE active_storage_attachments SET record_uuid = lists.uuid::text
        FROM lists WHERE record_type = 'List' AND record_id = lists.id
      SQL
      # Drop attachments orphaned by a since-deleted host record; their
      # record_uuid stays null and would block the NOT NULL constraint.
      execute "DELETE FROM active_storage_attachments WHERE record_uuid IS NULL"
    end

    # Pass 3a: drop foreign-key constraints so the old integer columns are free
    # to be dropped.
    def drop_foreign_keys
      FOREIGN_KEYS.each do |table, column, _parent|
        remove_foreign_key table, column: column
      end
    end

    # Pass 3b: promote the uuid column to primary key on every table. The
    # gen_random_uuid() default carries over to the new id column.
    def promote_primary_keys
      APP_TABLES.each do |table|
        remove_column table, :id
        rename_column table, :uuid, :id
        execute "ALTER TABLE #{table} ADD PRIMARY KEY (id)"
      end
    end

    # Pass 3c: promote the uuid foreign-key columns, restoring NOT NULL.
    def promote_foreign_keys
      FOREIGN_KEYS.each do |table, column, _parent|
        remove_column table, column
        rename_column table, uuid_column_name(column), column
        change_column_null table, column, false
      end

      remove_column :content_error_groups, :subject_id
      rename_column :content_error_groups, :subject_uuid, :subject_id

      remove_column :active_storage_attachments, :record_id
      rename_column :active_storage_attachments, :record_uuid, :record_id
      change_column_null :active_storage_attachments, :record_id, false
    end

    # Recreate every index that referenced a swapped foreign-key/polymorphic
    # column (dropping a column drops its indexes).
    def recreate_indexes
      add_index :articles, :website_id

      add_index :subscriptions, :user_id
      add_index :subscriptions, :website_id

      add_index :tags, :user_id
      add_index :tags, [ :user_id, :name ], unique: true

      add_index :lists, :user_id
      add_index :lists, [ :user_id, :slug ], unique: true, where: "(slug IS NOT NULL)"
      add_index :lists, [ :user_id, :title ], unique: true

      add_index :article_tags, :article_id
      add_index :article_tags, :tag_id
      add_index :article_tags, [ :article_id, :tag_id ], unique: true

      add_index :article_versions, :article_id
      add_index :article_versions, [ :article_id, :version ], unique: true

      add_index :list_articles, :article_id
      add_index :list_articles, :list_id
      add_index :list_articles, [ :list_id, :article_id ], unique: true

      add_index :user_articles, :user_id
      add_index :user_articles, :article_id

      add_index :content_error_groups,
        [ :fingerprint, :subject_type, :subject_id, :domain ],
        unique: true, name: "index_content_error_groups_on_fingerprint_and_subject"
      add_index :content_error_groups,
        [ :subject_type, :subject_id, :status, :last_seen_at ],
        name: "index_content_error_groups_on_subject_status_last_seen"

      add_index :active_storage_attachments,
        [ :record_type, :record_id, :name, :blob_id ],
        unique: true, name: "index_active_storage_attachments_uniqueness"
    end

    # Pass 3d: re-add the foreign-key constraints between uuid columns.
    def readd_foreign_keys
      FOREIGN_KEYS.each do |table, column, parent|
        add_foreign_key table, parent, column: column
      end
    end

    def uuid_column_name(column)
      column.to_s.sub(/_id\z/, "_uuid").to_sym
    end
end
