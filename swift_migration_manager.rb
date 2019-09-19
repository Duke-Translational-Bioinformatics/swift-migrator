require_relative 'dds_swift'
require_relative 'dds_s3'

class MigrationException < StandardError
end

class SwiftMigrationManager
  # mainly for rspec introspection
  attr_reader :swift, :s3, :manifest, :multipart_upload, :existing_object_metadata

  def initialize(logger, container, object, is_multipart_upload=false)
    @logger = logger
    @container = container
    @object = object
    @is_multipart_upload = is_multipart_upload

    @swift = DdsSwift.new
    @s3 = DdsS3.new

    if is_multipart_upload
      @manifest = @swift.get_object_manifest(@container, @object)
      existing_multipart_uploads = @s3.existing_multipart_uploads(@container, @object)
      @multipart_upload = existing_multipart_uploads.uploads.select {|u|
        u.key == object
      }.first || @s3.create_multipart_upload(@container, @object)
    else
      @manifest = @swift.get_object_metadata(@container, @object)
      @existing_object_metadata = @s3.head_object(@container, @object)
    end
  end

  def is_multipart_upload?
    @is_multipart_upload
  end

  def is_migrated?
    if is_multipart_upload?
      @s3.is_complete_multipart_upload?(@container, @object)
    else
      if @existing_object_metadata
        return @manifest["etag"] == @existing_object_metadata.etag.delete('""')
      else
        return false
      end
    end
  end

  def abort_migration
    return unless is_multipart_upload?
    @s3.abort_multipart_upload(@container, @object, @multipart_upload.upload_id)
  end

  def current_parts
    return unless is_multipart_upload?
    @s3.list_all_parts(@container, @object, @multipart_upload.upload_id)
  end

  def all_parts_migrated?
    return unless is_multipart_upload?
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
    return unless is_multipart_upload?
    parts ||= current_parts
    return false if parts.empty? || parts[part_number-1].nil?
    @manifest[part_number-1]["hash"] == parts[part_number-1].etag.delete('""')
  end

  def upload_part(part_number)
    return unless is_multipart_upload?
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
    return unless is_multipart_upload?
    return if is_migrated?
    if all_parts_migrated?
      check_parts = @manifest.map.with_index {|x,i| {etag: "\"#{x["hash"]}\"", part_number: i + 1}}
      @s3.complete_multipart_upload(@container, @object, @multipart_upload.upload_id, check_parts)
    else
      raise(MigrationException, "Cannot complete, all parts are not migrated!")
    end
  end

  def process_manifest
    return unless is_multipart_upload?
    @manifest.each_with_index do |chunk_summary, i|
      yield(i, chunk_summary)
    end
  end

  def migrate_object
    return if is_multipart_upload? || is_migrated?
    if @existing_object_metadata
      @logger.error "Something happened on previous upload, etag mismatch, will retry!"
      @s3.delete_object(@container, @object)
    end

    @existing_object_metadata = s3.put_object(
      @container,
      @object,
      @swift.get_object(@container,@object)
    )
    unless is_migrated?
      s3.delete_object(@container, @object)
      raise(MigrationException, "Could not upload, etag mismatch!")
    end
  end
end
