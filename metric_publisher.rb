require 'httparty'

class MetricPublisher
  def publish(job, metric, value)
    resp = HTTParty.post(
      "#{ENV['PUSHGATEWAY_URL']}/metrics/job/#{job}",
      body: "#{metric} #{value}"
    )
    return unless resp.response.code.to_i == 202
    true
  end
end
