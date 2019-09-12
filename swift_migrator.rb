require_relative 'swift_migration_manager'

container = '00d6f117-c7b5-4347-a82a-c04b7c6913db'
object = "420335c6-bb92-49cd-abe9-9aeb915b2f78"
migration_manager = SwiftMigrationManager.new(container, object)

if migration_manager.is_migrated?
  puts "All Complete"
  exit
end

migration_manager.process_manifest do |i|
  part_number = i + 1
  migration_manager.upload_part(part_number)
end

migration_manager.complete_migration
exit
#multipart_upload = existing_multipart_uploads.uploads.select {|u| u.key == object && u.upload_id == existing_multipart_upload_id }.first
