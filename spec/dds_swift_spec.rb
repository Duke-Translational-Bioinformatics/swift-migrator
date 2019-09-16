require 'webmock/rspec'
require_relative '../dds_swift'

describe DdsSwift do
  let(:swift) {
    DdsSwift.new
  }

  let(:swift_provider_version) { 'SWIFT_PROVIDER_VERSION' }
  let(:swift_provider_name) { 'SWIFT_PROVIDER_NAME' }
  let(:swift_provider_url_root) { 'https://SWIFT_PROVIDER_URL_ROOT' }
  let(:swift_provider_auth_uri) { 'SWIFT_PROVIDER_AUTH_URI' }
  let(:swift_user) { 'SWIFT_USER' }
  let(:swift_pass) { 'SWIFT_PASS' }

  before do
    ENV['SWIFT_PROVIDER_VERSION'] = swift_provider_version
    ENV['SWIFT_PROVIDER_NAME'] = swift_provider_name
    ENV['SWIFT_PROVIDER_URL_ROOT'] = swift_provider_url_root
    ENV['SWIFT_PROVIDER_AUTH_URI'] = swift_provider_auth_uri
    ENV['SWIFT_USER'] = swift_user
    ENV['SWIFT_PASS'] = swift_pass
  end

  describe 'interface' do
    subject { swift }

    it { is_expected.to respond_to(:root_path) }
    it { is_expected.to respond_to(:auth_header) }
    it { is_expected.to respond_to(:call_auth_uri) }
    it { is_expected.to respond_to(:auth_token) }
    it { is_expected.to respond_to(:storage_url) }
    it { is_expected.to respond_to(:get_account_info) }
    it { is_expected.to respond_to(:get_containers) }
    it { is_expected.to respond_to(:get_container_meta).with(1).arguments }
    it { is_expected.to respond_to(:get_container_objects).with(1).arguments }
    it { is_expected.to respond_to(:get_object_metadata).with(2).arguments }
    it { is_expected.to respond_to(:get_object_manifest).with(2).arguments }
    it { is_expected.to respond_to(:get_object).with(2).arguments }
    it { is_expected.to respond_to(:get_data).with(1).arguments }
  end

  describe '#root_path' do
    subject { swift.root_path }
    let(:expected_root_path) { "/#{swift_provider_version}/#{swift_provider_name}" }
    it { is_expected.to eq(expected_root_path) }
  end

  describe 'swift API' do
    let(:expected_auth_token) { SecureRandom.hex }
    let(:expected_storage_url) { 'https://storage.url' }
    let(:expected_auth_header_response) {{
      'X-Auth-Token' => expected_auth_token
    }}
    let(:container) { SecureRandom.uuid }
    let(:object) { SecureRandom.uuid }

    shared_context 'authenticated storage_url call' do
      before do
        expect(swift).to receive(:storage_url)
          .and_return(expected_storage_url)
        expect(swift).to receive(:auth_header)
          .and_return(expected_auth_header_response)
      end
    end

    shared_context 'swift api response' do
      before do
        if expected_exception
          stub_request(
            expected_action,
            expected_url,
          ).with(headers: expected_request_headers)
          .to_raise(expected_exception)
        else
          stub_request(
            expected_action,
            expected_url,
          ).with(headers: expected_request_headers)
          .to_return(status: expected_response_status, headers: expected_response_headers, body: expected_response_body)
        end
      end
    end

    describe '#call_auth_uri' do
      subject {
        swift.call_auth_uri
      }
      let(:expected_action) { :get }
      let(:expected_url) { "#{swift_provider_url_root}#{swift_provider_auth_uri}" }
      let(:expected_exception) { false }
      let(:expected_request_headers) {{
        'X-Auth-User' => swift_user,
        'X-Auth-Key' => swift_pass
      }}
      let(:expected_response_body) { '' }
      let(:expected_response_headers) {{
        'x-auth-uri' => 'x-auth-uri'
      }}
      include_context 'swift api response'

      context 'unexpected exception' do
        let(:expected_exception) { Exception }

        it {
          expect {
            subject
          }.to raise_error(SwiftException)
        }
      end

      context 'response not 200' do
        let(:expected_response_status) { 400 }

        it {
          expect {
            subject
          }.to raise_error(SwiftException)
        }
      end

      context 'success' do
        let(:expected_response_status) { 200 }

        it {
          expect {
            is_expected.to eq(expected_response_headers)
          }.not_to raise_error
        }
      end
    end

    describe '#auth_token' do
      subject {
        swift.auth_token
      }
      let(:expected_response) {{
        'x-auth-token' => expected_auth_token
      }}
      before do
        expect(swift).to receive(:call_auth_uri)
          .and_return(expected_response)
      end
      it { is_expected.to eq(expected_auth_token) }
    end

    describe '#storage_url' do
      subject {
        swift.storage_url
      }
      let(:expected_response) {{
        'x-storage-url' => expected_storage_url
      }}
      before do
        expect(swift).to receive(:call_auth_uri)
          .and_return(expected_response)
      end
      it { is_expected.to eq(expected_storage_url) }
    end

    describe '#auth_header' do
      subject {
        swift.auth_header
      }
      before do
        expect(swift).to receive(:auth_token)
          .and_return(expected_auth_token)
      end
      it { is_expected.to eq(expected_auth_header_response) }
    end

    describe '#get_account_info' do
      subject {
        swift.get_account_info
      }
      include_context 'authenticated storage_url call'
      let(:expected_action) { :get }
      let(:expected_url) { "#{expected_storage_url}" }
      let(:expected_exception) { false }
      let(:expected_request_headers) { expected_auth_header_response }
      let(:expected_response_body) { '' }
      let(:expected_response_headers) {{
        'x-something-something' => 'something'
      }}
      include_context 'swift api response'

      context 'unsuccessful response' do
        let(:expected_response_status) { 400 }
        it {
          expect {
            subject
          }.to raise_error(SwiftException)
        }
      end

      context '204 response' do
        let(:expected_response) { expected_response_headers }
        let(:expected_response_status) { 204 }
        it {
          expect {
            is_expected.to eq(expected_response)
          }.not_to raise_error
        }
      end

      context '200 response' do
        let(:expected_response) { expected_response_headers }
        let(:expected_response_status) { 200 }
        it {
          expect {
            is_expected.to eq(expected_response)
          }.not_to raise_error
        }
      end
    end

    describe '#get_containers' do
      subject {
        swift.get_containers
      }
      include_context 'authenticated storage_url call'
      let(:expected_action) { :get }
      let(:expected_url) { "#{expected_storage_url}" }
      let(:expected_exception) { false }
      let(:expected_request_headers) { expected_auth_header_response }
      let(:expected_response_body) { '' }
      let(:expected_response_headers) {{
        'x-something-something' => 'something'
      }}
      include_context 'swift api response'

      context 'unsuccessful response' do
        let(:expected_response_status) { 400 }
        it {
          expect {
            subject
          }.to raise_error(SwiftException)
        }
      end

      context '404 response' do
        let(:expected_response_status) { 404 }
        let(:expected_response) { [] }
        it {
          expect {
            is_expected.to eq(expected_response)
          }.not_to raise_error
        }
      end

      context '204 response' do
        let(:expected_response_status) { 204 }
        let(:expected_response) { [] }
        it {
          expect {
            is_expected.to eq(expected_response)
          }.not_to raise_error
        }
      end

      context '200 response' do
        let(:expected_response_status) { 200 }
        let(:expected_response_body) { "c1\nc2" }
        let(:expected_response) { ['c1','c2'] }
        it {
          expect {
            is_expected.to eq(expected_response)
          }.not_to raise_error
        }
      end
    end

    describe '#get_container_meta' do
      subject {
        swift.get_container_meta(container)
      }
      include_context 'authenticated storage_url call'
      let(:expected_action) { :head }
      let(:expected_url) { "#{expected_storage_url}/#{container}" }
      let(:expected_exception) { false }
      let(:expected_request_headers) { expected_auth_header_response }
      let(:expected_response_body) { '' }
      let(:expected_response_headers) {{
        'x-something-something' => 'something'
      }}
      include_context 'swift api response'

      context 'unsuccessful response' do
        let(:expected_response_status) { 400 }
        it {
          expect {
            subject
          }.to raise_error(SwiftException)
        }
      end

      context '404 response' do
        let(:expected_response_status) { 404 }
        let(:expected_response) { nil }
        it {
          expect {
            is_expected.to eq(expected_response)
          }.not_to raise_error
        }
      end

      context '204 response' do
        let(:expected_response_status) { 204 }
        let(:expected_response) { expected_response_headers }
        it {
          expect {
            is_expected.to eq(expected_response)
          }.not_to raise_error
        }
      end

      context '200 response' do
        let(:expected_response_status) { 200 }
        let(:expected_response) { expected_response_headers }
        it {
          expect {
            is_expected.to eq(expected_response)
          }.not_to raise_error
        }
      end
    end

    describe '#get_container_objects' do
      subject {
        swift.get_container_objects(container)
      }
      include_context 'authenticated storage_url call'
      let(:expected_action) { :get }
      let(:expected_url) { "#{expected_storage_url}/#{container}" }
      let(:expected_exception) { false }
      let(:expected_request_headers) { expected_auth_header_response }
      let(:expected_response_body) { '' }
      let(:expected_response_headers) {{
        'x-something-something' => 'something'
      }}
      include_context 'swift api response'

      context 'unsuccessful response' do
        let(:expected_response_status) { 400 }
        it {
          expect {
            subject
          }.to raise_error(SwiftException)
        }
      end

      context '404 response' do
        let(:expected_response_status) { 404 }
        let(:expected_response) { [] }
        it {
          expect {
            is_expected.to eq(expected_response)
          }.not_to raise_error
        }
      end

      context '204 response' do
        let(:expected_response_status) { 204 }
        let(:expected_response) { [] }
        it {
          expect {
            is_expected.to eq(expected_response)
          }.not_to raise_error
        }
      end

      context '200 response' do
        let(:expected_response_status) { 200 }
        let(:expected_response_body) { "o1\no2" }
        let(:expected_response) { ['o1','o2'] }
        it {
          expect {
            is_expected.to eq(expected_response)
          }.not_to raise_error
        }
      end
    end

    describe '#get_object_metadata' do
      subject {
        swift.get_object_metadata(container, object)
      }
      include_context 'authenticated storage_url call'
      let(:expected_action) { :head }
      let(:expected_url) { "#{expected_storage_url}/#{container}/#{object}" }
      let(:expected_exception) { false }
      let(:expected_request_headers) { expected_auth_header_response }
      let(:expected_response_body) { '' }
      let(:expected_response_headers) {{
        'x-something-something' => 'something'
      }}
      include_context 'swift api response'

      context 'unsuccessful response' do
        let(:expected_response_status) { 400 }
        it {
          expect {
            subject
          }.to raise_error(SwiftException)
        }
      end

      context '404 response' do
        let(:expected_response_status) { 404 }
        it {
          expect {
            subject
          }.to raise_error(SwiftException)
        }
      end

      context '204 response' do
        let(:expected_response_status) { 204 }
        let(:expected_response) { expected_response_headers }
        it {
          expect {
            is_expected.to eq(expected_response)
          }.not_to raise_error
        }
      end

      context '200 response' do
        let(:expected_response_status) { 200 }
        let(:expected_response) { expected_response_headers }
        it {
          expect {
            is_expected.to eq(expected_response)
          }.not_to raise_error
        }
      end
    end

    describe '#get_object_manifest' do
      subject {
        swift.get_object_manifest(container, object)
      }
      include_context 'authenticated storage_url call'
      let(:expected_action) { :get }
      let(:expected_url) { "#{expected_storage_url}/#{container}/#{object}?multipart-manifest=get" }
      let(:expected_exception) { false }
      let(:expected_request_headers) { expected_auth_header_response }
      let(:expected_response_body) { '' }
      let(:expected_response_headers) {{
        'x-something-something' => 'something'
      }}
      include_context 'swift api response'

      context 'unsuccessful response' do
        let(:expected_response_status) { 400 }
        it {
          expect {
            subject
          }.to raise_error(SwiftException)
        }
      end

      context '404 response' do
        let(:expected_response_status) { 404 }
        it {
          expect {
            subject
          }.to raise_error(SwiftException)
        }
      end

      context '204 response' do
        let(:expected_response_status) { 204 }
        let(:expected_response) { nil }
        it {
          expect {
            is_expected.to eq(expected_response)
          }.not_to raise_error
        }
      end

      context '200 response' do
        let(:expected_response_status) { 200 }
        let(:expected_response_body) { JSON.dump([{"hash" => "thehash"}]) }
        let(:expected_response) { expected_response_body }
        # technically, this method returns HTTParty resp.parsed_response
        # which is typically an object parsed from JSON, but this proved
        # challenging to mock
        it {
          expect {
            is_expected.to eq(expected_response)
          }.not_to raise_error
        }
      end
    end

    describe '#get_object' do
      subject {
        swift.get_object(container, object)
      }
      let(:expected_response) { 'The Data' }
      before do
        expect(swift).to receive(:get_data)
          .with("/#{container}/#{object}")
          .and_return(expected_response)
      end
      it { is_expected.to eq(expected_response) }
    end

    describe '#get_data' do
      subject {
        swift.get_data(expected_path)
      }
      include_context 'authenticated storage_url call'
      let(:expected_action) { :get }
      let(:expected_path) { '/path' }
      let(:expected_url) { "#{expected_storage_url}#{expected_path}" }
      let(:expected_exception) { false }
      let(:expected_request_headers) { expected_auth_header_response }
      let(:expected_response_body) { '' }
      let(:expected_response_headers) {{
        'x-something-something' => 'something'
      }}
      include_context 'swift api response'

      context 'unsuccessful response' do
        let(:expected_response_status) { 400 }
        it {
          expect {
            subject
          }.to raise_error(SwiftException)
        }
      end

      context '404 response' do
        let(:expected_response_status) { 404 }
        it {
          expect {
            subject
          }.to raise_error(SwiftException)
        }
      end

      context '204 response' do
        let(:expected_response_status) { 204 }
        let(:expected_response) { nil }
        it {
          expect {
            is_expected.to eq(expected_response)
          }.not_to raise_error
        }
      end

      context '200 response' do
        let(:expected_response_status) { 200 }
        let(:expected_response_body) { "The Data" }
        let(:expected_response) { expected_response_body }
        it {
          expect {
            is_expected.to eq(expected_response)
          }.not_to raise_error
        }
      end
    end
  end
end
