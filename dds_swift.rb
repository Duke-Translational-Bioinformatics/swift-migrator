#!/usr/local/bin/ruby
require 'httparty'

class SwiftException < StandardError
end

class DdsSwift
  def call_auth_uri
    begin
      @auth_uri_resp ||= HTTParty.get(
          "#{ENV['SWIFT_PROVIDER_URL_ROOT']}#{ENV['SWIFT_PROVIDER_AUTH_URI']}",
          headers: {
            'X-Auth-User' => ENV['SWIFT_USER'],
            'X-Auth-Key' => ENV['SWIFT_PASS']
          }
      )
    rescue Exception => e
      raise SwiftException, "Unexpected StorageProvider Error #{e.message}"
    end
    unless @auth_uri_resp.response.code.to_i == 200
      raise SwiftException, "Auth Failure: #{ @auth_uri_resp.body }"
    end
    @auth_uri_resp.headers
  end

  def auth_token
    call_auth_uri['x-auth-token']
  end

  def storage_url
    call_auth_uri['x-storage-url']
  end

  def auth_header
    {'X-Auth-Token' => auth_token}
  end

  def get_account_info
    resp = HTTParty.get(
      "#{storage_url}",
      headers: auth_header
    )
    ([200,204].include?(resp.response.code.to_i)) ||
      raise(SwiftException, resp.body)
    resp.headers
  end

  def get_containers
    resp = HTTParty.get(
      "#{storage_url}",
      headers: auth_header
    )
    return [] if resp.response.code.to_i == 404
    ([200,204].include?(resp.response.code.to_i)) ||
      raise(SwiftException, resp.body)
    return resp.body ? resp.body.split("\n") : []
  end

  def get_container_meta(container)
    resp = HTTParty.head(
      "#{storage_url}/#{container}",
      headers: auth_header
    )
    return if resp.response.code.to_i == 404
    ([200,204].include?(resp.response.code.to_i)) ||
      raise(SwiftException, resp.body)
     resp.headers
  end

  def get_container_objects(container)
    resp = HTTParty.get(
      "#{storage_url}/#{container}",
      headers: auth_header
    )
    return [] if resp.response.code.to_i == 404
    ([200,204].include?(resp.response.code.to_i)) ||
      raise(SwiftException, resp.body)
     return resp.body ? resp.body.split("\n") : []
  end

  def get_object_metadata(container, object)
    resp = HTTParty.head(
      "#{storage_url}/#{container}/#{object}",
      headers: auth_header
    )
    ([200,204].include?(resp.response.code.to_i)) ||
      raise(SwiftException, resp.body)
     resp.headers
  end

  def get_object_manifest(container, object)
    resp = HTTParty.get(
      "#{storage_url}/#{container}/#{object}?multipart-manifest=get",
      headers: auth_header
    )
    ([200,204].include?(resp.response.code.to_i)) ||
      raise(SwiftException, resp.body)
    resp.parsed_response
  end

  def get_object(container, object)
    get_data("/#{container}/#{object}")
  end

  def get_data(path)
    resp = HTTParty.get(
      "#{storage_url}#{path}",
      headers: auth_header
    )
    ([200,204].include?(resp.response.code.to_i)) ||
      raise(SwiftException, resp.body)
    resp.body
  end
end
