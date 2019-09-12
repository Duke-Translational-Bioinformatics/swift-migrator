require_relative 'dds_swift'
require_relative 'dds_s3'

swift = DdsSwift.new
container = '00d6f117-c7b5-4347-a82a-c04b7c6913db'
object = "420335c6-bb92-49cd-abe9-9aeb915b2f78"
manifest = swift.get_object_manifest(container, object)

s3 = DdsS3.new
if s3.is_complete_chunked_upload?(container, object)
  puts "All Complete"
  exit
end
existing_multipart_uploads = s3.existing_multipart_uploads(container, object)
multipart_upload = existing_multipart_uploads.uploads.select {|u| u.key == object }.first || s3.create_multipart_upload(container, object)

parts = s3.list_all_parts(container, object, multipart_upload.upload_id)
is_complete = false
if parts.length == manifest.length
  is_complete = true
  parts.each_index do |i|
    is_complete = manifest[i]["hash"] == parts[i].etag.delete('""')
    last unless is_complete
  end
end
if is_complete
  puts "All Complete"
  exit
end

manifest.each_with_index do |chunk_summary, i|
  next if parts.length > 0 && parts[i] && manifest[i]["hash"] == parts[i].etag.delete('"')
  part_number = i + 1
  resp = s3.upload_part(
    container,
    object,
    part_number,
    multipart_upload.upload_id,
    swift.get_data(chunk_summary["name"])
  )
  etag = resp.etag.delete('"')
  raise "Could not upload part #{part_number} hash mismatch!" unless manifest[i]["hash"] == etag
end

parts = s3.list_parts(container, object, multipart_upload.upload_id).parts.to_a
is_complete = false
if parts.length == manifest.length
  is_complete = true
  parts.each_index do |i|
    is_complete = manifest[i]["hash"] == parts[i].etag.delete('""')
    last unless is_complete
  end
end
if is_complete
  check_parts = manifest.map.with_index {|x,i| {etag: "\"#{x["hash"]}\"", part_number: i + 1}}
  s3.complete_multipart_upload(container, object, multipart_upload.upload_id, check_parts)
  puts "All Complete"
else
  raise "Something went wrong"
end
exit
#multipart_upload = existing_multipart_uploads.uploads.select {|u| u.key == object && u.upload_id == existing_multipart_upload_id }.first
