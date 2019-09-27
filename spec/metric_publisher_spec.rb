require 'webmock/rspec'
require_relative '../metric_publisher'

describe MetricPublisher do
  let(:push_gateway_url) { 'http://pushgateway:9091' }
  let(:publisher) {
    MetricPublisher.new
  }

  before do
    ENV['PUSHGATEWAY_URL'] = push_gateway_url
  end

  it { is_expected.to respond_to(:publish).with(3).arguments }

  describe '#publish' do
    let(:job_name) { 'job' }
    let(:metric_name) { 'metric' }
    let(:value) { 1 }
    let(:expected_url) { "#{push_gateway_url}/metrics/job/#{job_name}"}
    let(:expected_body) {
      "#{metric_name} #{value}"
    }

    subject {
      publisher.publish(job_name, metric_name, value)
    }

    before do
      stub_request(
        :post,
        expected_url,
      ).with(body: expected_body)
      .to_return(status: expected_response_status)
    end

    context 'success' do
      let(:expected_response_status) { 202 }
      it { is_expected.to be_truthy }
    end
    context 'failure' do
      let(:expected_response_status) { 404 }
      it { is_expected.to be_falsey }
    end
  end
end
