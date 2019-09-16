require_relative '../swift_migration_manager'
describe SwiftMigrationManager do
  shared_context 'mocked_s3' do
    let(:mocked_s3) { double(DdsS3) }
    before do
      allow(DdsSwift).to receive(:new)
        .and_return(mocked_swift)
    end
  end

  shared_context 'mocked_swift' do
    let(:mocked_swift) { double(DdsSwift) }

    before do
      allow(DdsS3).to receive(:new)
        .and_return(mocked_s3)
    end
  end

  shared_context 'initialization' do
    before do
      expect(mocked_swift).to receive(:get_object_manifest)
        .with(container, object)
        .and_return(mocked_manifest)
      expect(mocked_s3).to receive(:existing_multipart_uploads)
        .with(container, object)
        .and_return(mocked_empty_multipart_upload_response)
      expect(mocked_s3).to receive(:create_multipart_upload)
        .with(container, object)
        .and_return(mocked_multipart_upload)
    end
  end

  let(:container) { SecureRandom.uuid }
  let(:object) { SecureRandom.uuid }
  let(:swift_manager) {
    SwiftMigrationManager.new(container, object)
  }

  let(:first_part_hash) { SecureRandom.hex }
  let(:second_part_hash) { SecureRandom.hex }
  let(:mocked_manifest) {[
    {"hash" => first_part_hash, "name" => "p1" },
    {"hash" => second_part_hash, "name" => "p2" }
  ]}

  let(:multipart_upload_id) { SecureRandom.hex }
  let(:mocked_multipart_upload) {
    double('Mocked Multipart Upload',
      upload_id: multipart_upload_id,
      key: object
    )
  }

  let(:mocked_s3_parts) {[
    double('first s3 part', etag: first_part_hash),
    double('second s3 part', etag: second_part_hash)
  ]}

  let(:mocked_existing_multipart_upload_response) {
    double('Mocked Existing Multipart Upload Response',
      uploads: [ mocked_multipart_upload ]
    )
  }
  let(:mocked_empty_multipart_upload_response) {
    double('Mocked Empty Multipart Upload Response',
      uploads: []
    )
  }

  include_context 'mocked_s3'
  include_context 'mocked_swift'

  describe 'constructor' do
    context 'without arguments' do
      subject {
        SwiftMigrationManager.new
      }
      it {
        expect {
          subject
        }.to raise_error(ArgumentError)
      }
    end

    context 'without object' do
      subject {
        SwiftMigrationManager.new(container)
      }
      it {
        expect {
          subject
        }.to raise_error(ArgumentError)
      }
    end

    context 'with container, and object' do
      subject {
        swift_manager
      }

      context 'with existing multipart upload' do
        before do
          expect(mocked_swift).to receive(:get_object_manifest)
            .with(container, object)
            .and_return(mocked_manifest)
          expect(mocked_s3).to receive(:existing_multipart_uploads)
            .with(container, object)
            .and_return(mocked_existing_multipart_upload_response)
          expect(mocked_s3).not_to receive(:create_multipart_upload)
        end

        it 'should construct a SwiftMigrationManager with initialized s3, swift, manifest, and multipart_upload' do
          expect(subject).to be_a(SwiftMigrationManager)
          expect(subject.s3).to eq(mocked_s3)
          expect(subject.swift).to eq(mocked_swift)
          expect(subject.manifest).to eq(mocked_manifest)
          expect(subject.multipart_upload).to eq(mocked_multipart_upload)
        end
      end

      context 'without existing multipart_upload' do
        include_context 'initialization'

        it 'should construct a SwiftMigrationManager with initialized s3, swift, manifest, and multipart_upload' do
          expect(subject).to be_a(SwiftMigrationManager)
          expect(subject.s3).to eq(mocked_s3)
          expect(subject.swift).to eq(mocked_swift)
          expect(subject.manifest).to eq(mocked_manifest)
          expect(subject.multipart_upload).to eq(mocked_multipart_upload)
        end
      end
    end
  end

  describe 'interface' do
    subject {
      swift_manager
    }
    include_context 'initialization'

    it { is_expected.to respond_to(:is_migrated?) }
    it { is_expected.to respond_to(:abort_migration) }
    it { is_expected.to respond_to(:current_parts) }
    it { is_expected.to respond_to(:all_parts_migrated?) }
    it { is_expected.to respond_to(:part_migrated?).with(1).arguments }
    it { is_expected.to respond_to(:part_migrated?).with(2).arguments }
    it { is_expected.to respond_to(:upload_part).with(1).arguments }
    it { is_expected.to respond_to(:complete_migration) }
    it { is_expected.to respond_to(:process_manifest) }

    describe '#is_migrated?' do
      subject {
        swift_manager.is_migrated?
      }
      before do
        expect(mocked_s3).to receive(:is_complete_multipart_upload?)
          .with(container, object)
          .and_return(expected_response)
      end
      context 'already migrated' do
        let(:expected_response) { true }
        it { is_expected.to be_truthy }
      end

      context 'already migrated' do
        let(:expected_response) { false }
        it { is_expected.to be_falsey }
      end
    end

    describe '#abort_migration' do
      subject {
        swift_manager.abort_migration
      }
      before do
        expect(mocked_s3).to receive(:abort_multipart_upload)
          .with(container, object, multipart_upload_id)
      end
      it {
        expect {
          subject
        }.not_to raise_error
      }
    end

    describe '#current_parts' do
      subject {
        swift_manager.current_parts
      }
      before do
        expect(mocked_s3).to receive(:list_all_parts)
          .with(container, object, multipart_upload_id)
      end
      it {
        expect {
          subject
        }.not_to raise_error
      }
    end

    describe '#all_parts_migrated?' do
      subject {
        swift_manager.all_parts_migrated?
      }
      context 'when manifest parts are missing from s3 parts' do
        before do
          expect(swift_manager).to receive(:current_parts)
            .and_return([])
        end
        it { is_expected.to be_falsey }
      end

      context 'when a manifest part has not been migrated correctly' do
        before do
          expect(swift_manager).to receive(:current_parts)
            .and_return(mocked_s3_parts)
          expect(swift_manager).to receive(:part_migrated?)
            .with(1, mocked_s3_parts)
            .and_return(true)
          expect(swift_manager).to receive(:part_migrated?)
            .with(2, mocked_s3_parts)
            .and_return(false)
        end

        it { is_expected.to be_falsey }
      end

      context 'when all manifest parts are uploaded to s3' do
        before do
          expect(swift_manager).to receive(:current_parts)
            .and_return(mocked_s3_parts)
          expect(swift_manager).to receive(:part_migrated?)
            .with(1, mocked_s3_parts)
            .and_return(true)
          expect(swift_manager).to receive(:part_migrated?)
            .with(2, mocked_s3_parts)
            .and_return(true)
        end

        it { is_expected.to be_truthy }
      end
    end

    describe '#part_migrated?' do
      let(:part_number) { 1 }

      context 'called without parts' do
        subject {
          swift_manager.part_migrated?(part_number)
        }
        before do
          expect(swift_manager).to receive(:current_parts)
            .and_return(mocked_s3_parts)
        end
        it { is_expected.to be_truthy }
      end

      context 'called with parts' do
        subject {
          swift_manager.part_migrated?(part_number, mocked_s3_parts)
        }
        before do
          expect(swift_manager).not_to receive(:current_parts)
        end
        it { is_expected.to be_truthy }
      end

      context 'when parts is empty' do
        subject {
          swift_manager.part_migrated?(part_number, [])
        }
        it { is_expected.to be_falsey }
      end

      context 'with part_number is not defined in parts' do
        let(:part_number) { 4 }
        subject {
          swift_manager.part_migrated?(part_number, mocked_s3_parts)
        }
        it { is_expected.to be_falsey }
      end

      context 'when part_number manifest hash does not equal part etag' do
        let(:mocked_s3_parts) {[
          double('first s3 part', etag: SecureRandom.hex )
        ]}
        subject {
          swift_manager.part_migrated?(part_number, mocked_s3_parts)
        }
        it { is_expected.to be_falsey }
      end
    end

    describe '#upload_part' do
      let(:part_number) { 1 }
      subject {
        swift_manager.upload_part(part_number)
      }
      before do
        expect(swift_manager).to receive(:part_migrated?)
          .with(part_number)
          .and_return(part_is_migrated)
      end

      context 'when part is already migrated' do
        let(:part_is_migrated) { true }
        before do
          expect(mocked_s3).not_to receive(:upload_part)
        end
        it {
          expect {
            subject
          }.not_to raise_error
        }
      end

      context 'when part is not already migrated' do
        let(:part_is_migrated) { false }
        let(:part_data) { 'The Data' }
        before do
          expect(mocked_swift).to receive(:get_data)
            .with(mocked_manifest[part_number-1]["name"])
            .and_return(part_data)
          expect(mocked_s3).to receive(:upload_part)
            .with(
              container,
              object,
              part_number,
              multipart_upload_id,
              part_data
            ).and_return(expected_response)
        end
        context 'when uploaded part etag does not equal manifest hash' do
          let(:expected_response) {
            double('bad upload', etag: SecureRandom.hex )
          }
          it {
            expect {
              subject
            }.to raise_error(MigrationException)
          }
        end

        context 'when uploaded part etag matches manifest hash' do
          let(:expected_response) {
            double('good upload', etag: first_part_hash )
          }
          it {
            expect {
              subject
            }.not_to raise_error
          }
        end
      end
    end

    describe '#complete_migration' do
      subject {
        swift_manager.complete_migration
      }

      before do
        expect(swift_manager).to receive(:is_migrated?)
          .and_return(is_already_migrated)
      end

      context 'when is_migrated? is true' do
        let(:is_already_migrated) { true }
        before do
          expect(swift_manager).not_to receive(:all_parts_migrated?)
        end
        it {
          expect {
            subject
          }.not_to raise_error
        }
      end

      context 'when is_migrated? is false' do
        let(:is_already_migrated) { false }

        before do
          expect(swift_manager).to receive(:all_parts_migrated?)
            .and_return(all_parts_are_migrated)
        end

        context 'all_parts_migrated? is true' do
          let(:all_parts_are_migrated) { true }
          let(:expected_check_parts) { mocked_manifest.map.with_index {|x,i| {etag: "\"#{x["hash"]}\"", part_number: i + 1}} }

          before do
            expect(mocked_s3).to receive(:complete_multipart_upload)
              .with(container, object, multipart_upload_id, expected_check_parts)
          end
          it {
            expect {
              subject
            }.not_to raise_error
          }
        end

        context 'when all_parts_migrated? is false' do
          let(:all_parts_are_migrated) { false }

          before do
            expect(mocked_s3).not_to receive(:complete_multipart_upload)
          end
          it {
            expect {
              subject
            }.to raise_error(MigrationException)
          }
        end
      end
    end

    describe '#process_manifest' do
      it 'should iterate through the manifest and yield each entry with its index' do
        parts_seen = []
        swift_manager.process_manifest do |index, manifest_part|
          parts_seen[index] = manifest_part
        end
        expect(parts_seen).not_to be_empty
        parts_seen.each_with_index do |p, i|
          expect(mocked_manifest[i]).to eq(p)
        end
      end
    end
  end
end
