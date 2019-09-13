#!/usr/local/bin/ruby
require 'aws-sdk'

class S3Exception < StandardError
end

class IntegrityException < StandardError
end

class DdsS3
  def is_ready?
    begin
      !!list_buckets
    rescue S3Exception
      false
    end
  end

  def initialize_project(project)
    location = create_bucket(project)[:location]
    put_bucket_cors(project)
    location
  end

  def is_initialized?(project)
    head_bucket(project)
  end

  def is_complete_multipart_upload?(bucket, upload)
    head_object(bucket, upload)
  end

  # S3 Interface
  def client
    @client ||= Aws::S3::Client.new(
      region: 'us-east-1',
      force_path_style: true,
      access_key_id: ENV['S3_USER'],
      secret_access_key: ENV['S3_PASS'],
      endpoint: ENV['S3_PROVIDER_URL_ROOT']
    )
  end

  def list_buckets
    begin
      client.list_buckets.to_h[:buckets]
    rescue Aws::Errors::ServiceError => e
      raise(S3Exception, e.message)
    end
  end

  def create_bucket(bucket_name)
    begin
      client.create_bucket(bucket: bucket_name).to_h
    rescue Aws::Errors::ServiceError => e
      raise(S3Exception, e.message)
    end
  end

  def head_bucket(bucket_name)
    begin
      client.head_bucket(bucket: bucket_name).to_h
    rescue Aws::S3::Errors::NotFound
      false
    rescue Aws::Errors::ServiceError => e
      raise(S3Exception, e.message)
    end
  end

  def create_multipart_upload(bucket_name, object_key)
    begin
      client.create_multipart_upload(bucket: bucket_name, key: object_key)
    rescue Aws::Errors::ServiceError => e
      raise(S3Exception, e.message)
    end
  end

  def existing_multipart_uploads(bucket, object)
    begin
      client.list_multipart_uploads(bucket: bucket, prefix: object)
    rescue Aws::Errors::ServiceError => e
      raise(S3Exception, e.message)
    end
  end

  def upload_part(bucket, object, part_number, upload_id, body)
    begin
      client.upload_part(
        bucket: bucket,
        key: object,
        part_number: part_number,
        upload_id: upload_id,
        body: body
      )
    rescue Aws::S3::Errors::NotFound => e
      raise(S3Exception, e.message)
    rescue Aws::Errors::ServiceError => e
      raise(S3Exception, e.message)
    end
  end

  def abort_multipart_upload(bucket, object, upload_id)
    begin
      client.abort_multipart_upload(bucket: bucket, key: object, upload_id: upload_id)
    rescue Aws::S3::Errors::NotFound
      return
    rescue Aws::Errors::ServiceError => e
      raise(S3Exception, e.message)
    end
  end

  def list_parts(bucket, object, upload_id, start_after_part=nil)
    begin
      client.list_parts(bucket: bucket, key: object, upload_id: upload_id, part_number_marker: start_after_part)
    rescue Aws::S3::Errors::NotFound => e
      raise(S3Exception, e.message)
    rescue Aws::Errors::ServiceError => e
      raise(S3Exception, e.message)
    end
  end

  def list_all_parts(bucket, object, upload_id)
    parts = []
    last_part_number = nil
    list_parts_response = list_parts(bucket, object, upload_id)

    while (list_parts_response.is_truncated)
      parts += list_parts_response.parts
      last_part_number = list_parts_response.parts.last.part_number
      list_parts_response = list_parts(bucket, object, upload_id, last_part_number)
    end

    parts += list_parts_response.parts
    parts
  end

  def complete_multipart_upload(bucket_name, object_key, upload_id, parts)
    begin
      client.complete_multipart_upload(bucket: bucket_name, key: object_key, upload_id: upload_id, multipart_upload: { parts: parts })
    rescue Aws::Errors::ServiceError => e
      raise(S3Exception, e.message)
    end
  end

  def head_object(bucket_name, object_key)
    begin
      client.head_object(bucket: bucket_name, key: object_key)
    rescue Aws::S3::Errors::NotFound
      false
    rescue Aws::Errors::ServiceError => e
      raise(S3Exception, e.message)
    end
  end

  def delete_object(bucket_name, object_key)
    begin
      client.delete_object(bucket: bucket_name, key: object_key)
    rescue Aws::Errors::ServiceError => e
      raise(S3Exception, e.message)
    end
  end

  private

  def put_bucket_cors(bucket_name)
    begin
      client.put_bucket_cors(
        bucket: bucket_name,
        cors_configuration: {
          cors_rules: [{
            allowed_headers: ['*'],
            allowed_methods: ['GET','PUT','HEAD','POST','DELETE'],
            allowed_origins: ['*']
          }]
        }
      ).to_h
    rescue Aws::Errors::ServiceError => e
      raise(S3Exception, e.message)
    end
  end
end
