require_relative '../dds_s3'

describe DdsS3 do
  let(:s3) { DdsS3.new }
  let(:s3_user) { 'S3_USER' }
  let(:s3_pass) { 'S3_PASS' }
  let(:s3_provider_url_root) { 'S3_PROVIDER_URL_ROOT' }
  let(:expected_bucket) { SecureRandom.uuid }
  let(:expected_object) { SecureRandom.uuid }

  before do
    ENV['S3_USER'] = s3_user
    ENV['S3_PASS'] = s3_pass
    ENV['S3_PROVIDER_URL_ROOT'] = s3_provider_url_root
  end

  describe 'interface' do
    subject { s3 }

    it { is_expected.to respond_to(:is_ready?) }
    it { is_expected.to respond_to(:initialize_project).with(1).argument }
    it { is_expected.to respond_to(:is_initialized?).with(1).argument }
    it { is_expected.to respond_to(:client) }
    it { is_expected.to respond_to(:list_buckets) }
    it { is_expected.to respond_to(:create_bucket).with(1).argument }
    it { is_expected.to respond_to(:head_bucket).with(1).argument }
    it { is_expected.to respond_to(:create_multipart_upload).with(2).arguments }
    it { is_expected.to respond_to(:existing_multipart_uploads).with(2).arguments }
    it { is_expected.to respond_to(:upload_part).with(5).arguments }
    it { is_expected.to respond_to(:abort_multipart_upload).with(3).arguments }
    it { is_expected.to respond_to(:list_parts).with(3).arguments }
    it { is_expected.to respond_to(:list_parts).with(4).arguments }
    it { is_expected.to respond_to(:list_all_parts).with(3).arguments }
    it { is_expected.to respond_to(:complete_multipart_upload).with(4).arguments }
    it { is_expected.to respond_to(:is_complete_multipart_upload?).with(2).arguments }
    it { is_expected.to respond_to(:head_object).with(2).arguments }
    it { is_expected.to respond_to(:delete_object).with(2).arguments }
  end

  describe '#is_ready?' do
    subject {
      s3.is_ready?
    }
    context 'when not ready' do
      before do
        expect(s3).to receive(:list_buckets).and_raise(S3Exception)
      end
      it { is_expected.to be_falsey }
    end

    context 'when ready' do
      let(:buckets) {
        [{name: "bucket", creation_date: DateTime.now}]
      }
      before do
        expect(s3).to receive(:list_buckets)
          .and_return(buckets)
      end
      it { is_expected.to be_truthy }
    end
  end

  describe '#initialize_project' do
    let(:project) { SecureRandom.uuid }
    let(:expected_location) { 'location' }
    let(:create_bucket_response) {
      {
        location: expected_location
      }
    }
    subject {
      s3.initialize_project(project)
    }

    before do
      expect(s3).to receive(:create_bucket)
        .with(project)
        .and_return(create_bucket_response)

      expect(s3).to receive(:put_bucket_cors)
        .with(project)
    end

    it { is_expected.to eq(expected_location) }
  end

  describe '#is_initialized?' do
    let(:project) { 'project' }
    subject { s3.is_initialized?(project) }

    before do
      expect(s3).to receive(:head_bucket)
        .with(project)
        .and_return(true)
    end
    it { is_expected.to be_truthy }
  end

  describe '#is_complete_multipart_upload?' do
    subject {
      s3.is_complete_multipart_upload?(expected_bucket, expected_object)
    }
    before do
      expect(s3).to receive(:head_object)
        .with(expected_bucket, expected_object)
        .and_return(true)
    end
    it { is_expected.to be_truthy }
  end

  describe 'S3 client methods' do
    let(:stubbed_client) {
      Aws::S3::Client.new(stub_responses: true)
    }
    let(:expected_upload_id) { SecureRandom.hex }
    let(:expected_part_number) { 3 }
    let(:expected_etag) { SecureRandom.hex }

    before do
      expect(Aws::S3::Client).to receive(:new)
        .with(
          region: 'us-east-1',
          force_path_style: true,
          access_key_id: s3_user,
          secret_access_key: s3_pass,
          endpoint: s3_provider_url_root
        ).and_return(stubbed_client)
    end

    describe '#client' do
      subject {
        s3.client
      }
      it 'should create an S3 client' do
        expect{
          is_expected.to eq(stubbed_client)
        }.not_to raise_error
      end
    end

    describe '#list_buckets' do
      subject {
        s3.list_buckets
      }
      let(:bucket_array) { [] }
      let(:expected_response) { { buckets: bucket_array } }
      before(:example) do
        s3.client.stub_responses(:list_buckets, expected_response)
      end

      it { is_expected.to eq([]) }

      context 'with buckets' do
        let(:bucket_array) { [{ name: SecureRandom.uuid }] }
        it { is_expected.to eq(bucket_array) }
      end

      context 'when an unexpected S3 error is thrown' do
        let(:expected_response) { 'Unexpected' }
        it 'raises a S3Exception' do
          expect { subject }.to raise_error(S3Exception)
        end
      end
    end

    describe '#create_bucket' do
      subject { s3.create_bucket(expected_bucket) }
      let(:expected_response) { { location: "/#{expected_bucket}" } }

      before(:example) do
        s3.client.stub_responses(:create_bucket, expected_response)
      end
      after(:example) do
        expect(s3.client.api_requests.first).not_to be_nil
        expect(s3.client.api_requests.first[:params][:bucket]).to eq(expected_bucket)
      end
      it { is_expected.to eq(expected_response) }

      context 'when an unexpected S3 error is thrown' do
        let(:expected_response) { 'Unexpected' }
        it 'raises a S3Exception' do
          expect { subject }.to raise_error(S3Exception)
        end
      end
    end

    describe '#head_bucket' do
      subject { s3.head_bucket(expected_bucket) }
      let(:expected_response) { {} }

      before(:example) do
        s3.client.stub_responses(:head_bucket, expected_response)
      end
      after(:example) do
        expect(s3.client.api_requests.first).not_to be_nil
        expect(s3.client.api_requests.first[:params][:bucket]).to eq(expected_bucket)
      end
      it { is_expected.to eq(expected_response) }

      context 'when bucket does not exist' do
        let(:expected_response) { 'NotFound' }
        it 'rescues from NoSuchBucket exception and returns false' do
          expect {
            is_expected.to be_falsey
          }.not_to raise_error
        end
      end

      context 'when an unexpected S3 error is thrown' do
        let(:expected_response) { 'Unexpected' }
        it 'raises a S3Exception' do
          expect { subject.head_bucket(expected_bucket) }.to raise_error(S3Exception)
        end
      end
    end

    describe '#create_multipart_upload' do
      subject {
        s3.create_multipart_upload(expected_bucket, expected_object)
      }

      let(:expected_response) { {
        bucket: expected_bucket,
        key: expected_object,
        upload_id: expected_upload_id
      } }
      before(:example) do
        s3.client.stub_responses(:create_multipart_upload, expected_response)
      end
      after(:example) do
        expect(s3.client.api_requests.first).not_to be_nil
        expect(s3.client.api_requests.first[:params][:bucket]).to eq(expected_bucket)
        expect(s3.client.api_requests.first[:params][:key]).to eq(expected_object)
      end
      it { expect(subject.upload_id).to eq(expected_upload_id) }

      context 'when an unexpected S3 error is thrown' do
        let(:expected_response) { 'Unexpected' }
        it 'raises a S3Exception' do
          expect { subject }.to raise_error(S3Exception)
        end
      end
    end

    describe '#existing_multipart_uploads' do
      subject {
        s3.existing_multipart_uploads(expected_bucket, expected_object)
      }
      let(:expected_response) {{
        bucket: expected_bucket,
        uploads: [
          {
            key: expected_object,
            upload_id: expected_upload_id
          }
        ]
      }}

      before(:example) do
        s3.client.stub_responses(:list_multipart_uploads, expected_response)
      end
      after(:example) do
        expect(s3.client.api_requests.first).not_to be_nil
        expect(s3.client.api_requests.first[:params][:bucket]).to eq(expected_bucket)
        expect(s3.client.api_requests.first[:params][:prefix]).to eq(expected_object)
      end
      it { expect(subject.uploads[0].upload_id).to eq(expected_upload_id) }

      context 'when an unexpected S3 error is thrown' do
        let(:expected_response) { 'Unexpected' }
        it 'raises a S3Exception' do
          expect { subject }.to raise_error(S3Exception)
        end
      end
    end

    describe '#upload_part' do
      let(:expected_body) { 'the body' }
      subject {
        s3.upload_part(
          expected_bucket,
          expected_object,
          expected_part_number,
          expected_upload_id,
          expected_body
        )
      }
      let(:expected_response) {{
        etag: expected_etag
      }}

      before(:example) do
        s3.client.stub_responses(:upload_part, expected_response)
      end
      after(:example) do
        expect(s3.client.api_requests.first).not_to be_nil
        expect(s3.client.api_requests.first[:params][:bucket]).to eq(expected_bucket)
        expect(s3.client.api_requests.first[:params][:key]).to eq(expected_object)
        expect(s3.client.api_requests.first[:params][:part_number]).to eq(expected_part_number)
        expect(s3.client.api_requests.first[:params][:upload_id]).to eq(expected_upload_id)
        expect(s3.client.api_requests.first[:params][:body]).to eq(expected_body)
      end

      it { expect(subject.etag).to eq(expected_etag) }

      context 'multipart_upload is not found' do
        let(:expected_response) { 'NotFound' }
        it 'raises a S3Exception' do
          expect { subject }.to raise_error(S3Exception)
        end
      end

      context 'when an unexpected S3 error is thrown' do
        let(:expected_response) { 'Unexpected' }
        it 'raises a S3Exception' do
          expect { subject }.to raise_error(S3Exception)
        end
      end
    end

    describe '#abort_multipart_upload' do
      subject {
        s3.abort_multipart_upload(expected_bucket, expected_object, expected_upload_id)
      }
      let(:expected_response) {{}}
      before(:example) do
        s3.client.stub_responses(:abort_multipart_upload, expected_response)
      end
      after(:example) do
        expect(s3.client.api_requests.first).not_to be_nil
        expect(s3.client.api_requests.first[:params][:bucket]).to eq(expected_bucket)
        expect(s3.client.api_requests.first[:params][:key]).to eq(expected_object)
        expect(s3.client.api_requests.first[:params][:upload_id]).to eq(expected_upload_id)
      end

      it { is_expected.to be }

      context 'multipart_upload is not found' do
        let(:expected_response) { 'NotFound' }
        it 'masks error and returns' do
          expect { subject }.not_to raise_error
        end
      end

      context 'when an unexpected S3 error is thrown' do
        let(:expected_response) { 'Unexpected' }
        it 'raises a S3Exception' do
          expect { subject }.to raise_error(S3Exception)
        end
      end
    end

    describe '#list_parts' do
      let(:expected_part) {{
        etag: expected_etag,
        part_number: expected_part_number
      }}
      let(:expected_parts) {[
        expected_part
      ]}
      let(:expected_response) {{
        bucket: expected_bucket,
        key: expected_object,
        upload_id: expected_upload_id,
        parts: expected_parts
      }}
      before(:example) do
        s3.client.stub_responses(:list_parts, expected_response)
      end

      context 'without start_after' do
        subject {
          s3.list_parts(expected_bucket, expected_object, expected_upload_id)
        }
        after(:example) do
          expect(s3.client.api_requests.first).not_to be_nil
          expect(s3.client.api_requests.first[:params][:bucket]).to eq(expected_bucket)
          expect(s3.client.api_requests.first[:params][:key]).to eq(expected_object)
          expect(s3.client.api_requests.first[:params][:upload_id]).to eq(expected_upload_id)
          expect(s3.client.api_requests.first[:params][:part_number_marker]).to be_nil
        end
        it { expect(subject.parts.length).to eq(expected_parts.length) }

        context 'multipart_upload is not found' do
          let(:expected_response) { 'NotFound' }
          it 'raises a S3Exception' do
            expect { subject }.to raise_error(S3Exception)
          end
        end

        context 'when an unexpected S3 error is thrown' do
          let(:expected_response) { 'Unexpected' }
          it 'raises a S3Exception' do
            expect { subject }.to raise_error(S3Exception)
          end
        end
      end

      context 'with start_after' do
        let(:expected_started_after) { 2 }
        subject {
          s3.list_parts(expected_bucket, expected_object, expected_upload_id, expected_started_after)
        }
        after(:example) do
          expect(s3.client.api_requests.first).not_to be_nil
          expect(s3.client.api_requests.first[:params][:bucket]).to eq(expected_bucket)
          expect(s3.client.api_requests.first[:params][:key]).to eq(expected_object)
          expect(s3.client.api_requests.first[:params][:upload_id]).to eq(expected_upload_id)
          expect(s3.client.api_requests.first[:params][:part_number_marker]).to eq(expected_started_after)
        end
        it { expect(subject.parts.length).to eq(expected_parts.length) }

        context 'multipart_upload is not found' do
          let(:expected_response) { 'NotFound' }
          it 'raises a S3Exception' do
            expect { subject }.to raise_error(S3Exception)
          end
        end

        context 'when an unexpected S3 error is thrown' do
          let(:expected_response) { 'Unexpected' }
          it 'raises a S3Exception' do
            expect { subject }.to raise_error(S3Exception)
          end
        end
      end
    end

    describe '#list_all_parts' do
      subject {
        s3.list_all_parts(expected_bucket, expected_object, expected_upload_id)
      }

      context 'when first list_parts call returns all parts' do
        let(:expected_part) {{
          etag: expected_etag,
          part_number: expected_part_number
        }}
        let(:expected_parts) {[
          expected_part
        ]}
        let(:expected_response) {{
          bucket: expected_bucket,
          key: expected_object,
          upload_id: expected_upload_id,
          parts: expected_parts
        }}
        before(:example) do
          s3.client.stub_responses(:list_parts, expected_response)
        end
        it { expect(subject.length).to eq(expected_parts.length) }
      end

      context 'when multiple list_parts calls are required to gather all parts' do
        let(:expected_first_part) {{
          etag: expected_etag,
          part_number: expected_part_number
        }}
        let(:expected_first_response_parts) {[
          expected_first_part
        ]}
        let(:expected_first_response) {{
          bucket: expected_bucket,
          key: expected_object,
          upload_id: expected_upload_id,
          is_truncated: true,
          parts: expected_first_response_parts
        }}
        let(:expected_second_etag) { SecureRandom.hex }
        let(:expected_second_part_number) { expected_part_number + 1 }
        let(:expected_second_part) {{
          etag: expected_second_etag,
          part_number: expected_second_part_number
        }}
        let(:expected_parts) {[
          expected_first_part,
          expected_second_part
        ]}
        let(:expected_second_response_parts) {[
          expected_second_part
        ]}
        let(:expected_second_response) {{
          bucket: expected_bucket,
          key: expected_object,
          upload_id: expected_upload_id,
          parts: expected_second_response_parts
        }}

        before do
          s3.client.stub_responses(:list_parts, -> (context) {
            if context.params[:part_number_marker] == expected_part_number
              expected_second_response
            else
              expected_first_response
            end
          })
        end
        it { expect(subject.length).to eq(expected_parts.length) }
      end
    end

    describe '#complete_multipart_upload' do
      let(:expected_parts) {[
        {etag: "\"#{expected_etag}\"", part_number: expected_part_number}
      ]}
      subject {
        s3.complete_multipart_upload(
          expected_bucket,
          expected_object,
          expected_upload_id,
          expected_parts
        )
      }
      let(:expected_multipart_etag) { SecureRandom.hex }
      let(:expected_location) { "/#{expected_bucket}" }
      let(:expected_response) { {
        bucket: expected_bucket,
        etag: "\"#{expected_multipart_etag}\"",
        key: expected_object,
        location: expected_location
      } }
      before do
        s3.client.stub_responses(:complete_multipart_upload, expected_response)
      end
      it { expect(subject.location).to eq(expected_location) }

      context 'multipart_upload is not found' do
        let(:expected_response) { 'NotFound' }
        it 'raises a S3Exception' do
          expect { subject }.to raise_error(S3Exception)
        end
      end

      context 'when an unexpected S3 error is thrown' do
        let(:expected_response) { 'Unexpected' }
        it 'raises a S3Exception' do
          expect { subject }.to raise_error(S3Exception)
        end
      end
    end

    describe '#head_object' do
      subject {
        s3.head_object(expected_bucket, expected_object)
      }
      let(:expected_response) {{
        etag: expected_etag
      }}
      before(:example) do
        s3.client.stub_responses(:head_object, expected_response)
      end
      after(:example) do
        expect(s3.client.api_requests.first).not_to be_nil
        expect(s3.client.api_requests.first[:params][:bucket]).to eq(expected_bucket)
        expect(s3.client.api_requests.first[:params][:key]).to eq(expected_object)
      end

      it { expect(subject.etag).to eq(expected_etag) }

      context 'upload is not found' do
        let(:expected_response) { 'NotFound' }
        it 'masks error and returns' do
          expect { is_expected.to be_falsey }.not_to raise_error
        end
      end

      context 'when an unexpected S3 error is thrown' do
        let(:expected_response) { 'Unexpected' }
        it 'raises a S3Exception' do
          expect { subject }.to raise_error(S3Exception)
        end
      end
    end

    describe '#delete_object' do
      subject {
        s3.delete_object(expected_bucket, expected_object)
      }
      let(:expected_response) {{
      }}
      before(:example) do
        s3.client.stub_responses(:delete_object, expected_response)
      end
      after(:example) do
        expect(s3.client.api_requests.first).not_to be_nil
        expect(s3.client.api_requests.first[:params][:bucket]).to eq(expected_bucket)
        expect(s3.client.api_requests.first[:params][:key]).to eq(expected_object)
      end

      it { expect(subject).to be }

      context 'when an unexpected S3 error is thrown' do
        let(:expected_response) { 'Unexpected' }
        it 'raises a S3Exception' do
          expect { subject }.to raise_error(S3Exception)
        end
      end
    end
  end
end
