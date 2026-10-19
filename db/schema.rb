# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_31_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "article_tags", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "article_id", null: false
    t.datetime "created_at", null: false
    t.uuid "tag_id", null: false
    t.datetime "updated_at", null: false
    t.index ["article_id", "tag_id"], name: "index_article_tags_on_article_id_and_tag_id", unique: true
    t.index ["article_id"], name: "index_article_tags_on_article_id"
    t.index ["tag_id"], name: "index_article_tags_on_tag_id"
  end

  create_table "article_versions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "article_id", null: false
    t.string "content_hash", null: false
    t.text "content_html"
    t.text "content_md"
    t.datetime "created_at", null: false
    t.date "publication_date"
    t.string "title"
    t.integer "version", null: false
    t.integer "word_count"
    t.index ["article_id", "version"], name: "index_article_versions_on_article_id_and_version", unique: true
    t.index ["article_id"], name: "index_article_versions_on_article_id"
  end

  create_table "articles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "content_fetch_failed_at"
    t.string "content_hash"
    t.text "content_html"
    t.text "content_md"
    t.datetime "created_at", null: false
    t.string "failure_reason"
    t.datetime "last_content_fetched_at"
    t.date "publication_date"
    t.string "raw_published_at"
    t.string "slug"
    t.string "status"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.uuid "website_id", null: false
    t.integer "word_count"
    t.index ["content_fetch_failed_at"], name: "index_articles_on_content_fetch_failed_at"
    t.index ["content_hash"], name: "index_articles_on_content_hash"
    t.index ["url"], name: "index_articles_on_url", unique: true
    t.index ["website_id"], name: "index_articles_on_website_id"
  end

  create_table "content_error_groups", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "active_job_id"
    t.integer "attempt"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "domain"
    t.string "exception_class"
    t.string "fingerprint", null: false
    t.datetime "first_seen_at", null: false
    t.string "http_method"
    t.integer "http_status"
    t.json "job_arguments"
    t.string "job_class"
    t.datetime "last_seen_at", null: false
    t.text "message", null: false
    t.integer "occurrences_count", default: 1, null: false
    t.string "operation", null: false
    t.string "phase", null: false
    t.string "queue_name"
    t.json "response_headers"
    t.string "severity", default: "error", null: false
    t.string "status", default: "open", null: false
    t.uuid "subject_id"
    t.string "subject_type"
    t.datetime "updated_at", null: false
    t.text "url"
    t.index ["domain", "status", "last_seen_at"], name: "index_content_error_groups_on_domain_status_last_seen"
    t.index ["fingerprint", "subject_type", "subject_id", "domain"], name: "index_content_error_groups_on_fingerprint_and_subject", unique: true
    t.index ["status", "last_seen_at"], name: "index_content_error_groups_on_status_and_last_seen_at"
    t.index ["subject_type", "subject_id", "status", "last_seen_at"], name: "index_content_error_groups_on_subject_status_last_seen"
  end

  create_table "email_sends", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "count", default: 0, null: false
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.datetime "updated_at", null: false
    t.index ["date"], name: "index_email_sends_on_date", unique: true
  end

  create_table "list_articles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "article_id", null: false
    t.datetime "created_at", null: false
    t.uuid "list_id", null: false
    t.integer "position"
    t.datetime "updated_at", null: false
    t.index ["article_id"], name: "index_list_articles_on_article_id"
    t.index ["list_id", "article_id"], name: "index_list_articles_on_list_id_and_article_id", unique: true
    t.index ["list_id"], name: "index_list_articles_on_list_id"
  end

  create_table "lists", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "public", default: false, null: false
    t.string "public_id", limit: 8, null: false
    t.string "slug"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["public_id"], name: "index_lists_on_public_id", unique: true
    t.index ["user_id", "slug"], name: "index_lists_on_user_id_and_slug", unique: true, where: "(slug IS NOT NULL)"
    t.index ["user_id", "title"], name: "index_lists_on_user_id_and_title", unique: true
    t.index ["user_id"], name: "index_lists_on_user_id"
  end

  create_table "subscriptions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_seen_at"
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.uuid "website_id", null: false
    t.index ["user_id", "website_id"], name: "index_subscriptions_on_user_id_and_website_id", unique: true
    t.index ["user_id"], name: "index_subscriptions_on_user_id"
    t.index ["website_id"], name: "index_subscriptions_on_website_id"
  end

  create_table "tags", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["user_id", "name"], name: "index_tags_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_tags_on_user_id"
  end

  create_table "user_articles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "article_id", null: false
    t.datetime "created_at", null: false
    t.datetime "read_at"
    t.datetime "removed_at"
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["article_id"], name: "index_user_articles_on_article_id"
    t.index ["user_id", "article_id"], name: "index_user_articles_on_user_id_and_article_id", unique: true
    t.index ["user_id"], name: "index_user_articles_on_user_id"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.string "email"
    t.datetime "email_confirmation_sent_at"
    t.datetime "email_confirmed_at"
    t.string "fullname"
    t.string "handle"
    t.string "password_digest"
    t.json "settings", default: {}, null: false
    t.string "unconfirmed_email"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["handle"], name: "index_users_on_handle", unique: true
  end

  create_table "websites", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.float "archive_confidence_score"
    t.string "archive_detection_method"
    t.boolean "archive_paginated", default: false, null: false
    t.string "archive_url"
    t.datetime "created_at", null: false
    t.string "domain", null: false
    t.datetime "last_crawled_at"
    t.string "name"
    t.datetime "pagination_completed_at"
    t.string "pagination_halted_reason"
    t.integer "pagination_last_page_scraped"
    t.integer "pagination_page_limit"
    t.integer "pagination_post_limit"
    t.integer "pagination_total_pages_found"
    t.text "processing_error_message"
    t.datetime "processing_failed_at"
    t.datetime "processing_started_at"
    t.string "processing_status", default: "idle", null: false
    t.string "title_suffix_pattern"
    t.datetime "updated_at", null: false
    t.index ["processing_status"], name: "index_websites_on_processing_status"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "article_tags", "articles"
  add_foreign_key "article_tags", "tags"
  add_foreign_key "article_versions", "articles"
  add_foreign_key "articles", "websites"
  add_foreign_key "list_articles", "articles"
  add_foreign_key "list_articles", "lists"
  add_foreign_key "lists", "users"
  add_foreign_key "subscriptions", "users"
  add_foreign_key "subscriptions", "websites"
  add_foreign_key "tags", "users"
  add_foreign_key "user_articles", "articles"
  add_foreign_key "user_articles", "users"
end
