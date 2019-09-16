require_relative 'dds_swift'
require_relative 'dds_s3'

class MigrationException < StandardError
end

class SwiftMigrationManager
  # mainly for rspec introspection
  attr_reader :swift, :s3, :manifest, :multipart_upload

  def initialize(container, object)
    @container = container
    @object = object
    @swift = DdsSwift.new
    @s3 = DdsS3.new

    @manifest = @swift.get_object_manifest(@container, @object)
    existing_multipart_uploads = @s3.existing_multipart_uploads(@container, @object)
    @multipart_upload = existing_multipart_uploads.uploads.select {|u|
      u.key == object
    }.first || @s3.create_multipart_upload(@container, @object)
  end

  def is_migrated?
    @s3.is_complete_multipart_upload?(@container, @object)
  end

  def abort_migration
    @s3.abort_multipart_upload(@container, @object, @multipart_upload.upload_id)
  end

  def current_parts
    @s3.list_all_parts(@container, @object, @multipart_upload.upload_id)
  end

  def all_parts_migrated?
    parts = current_parts
    is_complete = false
    if parts.length == @manifest.length
      is_complete = true
      parts.each_index do |i|
        part_number = i + 1
        is_complete = part_migrated?(part_number, parts)
        break unless is_complete
      end
    end
    is_complete
  end

  def part_migrated?(part_number, parts=nil)
    parts ||= current_parts
    return false if parts.empty? || parts[part_number-1].nil?
    @manifest[part_number-1]["hash"] == parts[part_number-1].etag.delete('""')
  end

  def upload_part(part_number)
    return if part_migrated?(part_number)
    manifest_index = part_number - 1
    chunk_summary = @manifest[manifest_index]
    resp = @s3.upload_part(
      @container,
      @object,
      part_number,
      @multipart_upload.upload_id,
      @swift.get_data(chunk_summary["name"])
    )
    etag = resp.etag.delete('"')
    unless @manifest[manifest_index]["hash"] == etag
      raise(MigrationException, "Could not upload part #{part_number}: hash mismatch!")
    end
  end

  def complete_migration
    return if is_migrated?
    if all_parts_migrated?
      check_parts = @manifest.map.with_index {|x,i| {etag: "\"#{x["hash"]}\"", part_number: i + 1}}
      @s3.complete_multipart_upload(@container, @object, @multipart_upload.upload_id, check_parts)
    else
      raise(MigrationException, "Cannot complete, all parts are not migrated!")
    end
  end

  def process_manifest
    @manifest.each_with_index do |chunk_summary, i|
      yield(i, chunk_summary)
    end
  end
end
