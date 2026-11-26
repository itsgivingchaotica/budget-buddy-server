# No financial text in logs: when a JSON body doesn't parse, Rails logs the
# raw body ("Error occurred while parsing request parameters. Contents: …")
# at debug level. This answers malformed JSON with a bare 400 before Rails
# parses it, and logs only that it happened.
class JsonBodyGuard
  def initialize(app) = @app = app

  def call(env)
    request = Rack::Request.new(env)
    return @app.call(env) unless request.media_type.to_s.end_with?("json") && request.content_length.to_i.positive?

    body = request.body.read
    request.body.rewind
    JSON.parse(body)
    @app.call(env)
  rescue JSON::ParserError, EncodingError
    Rails.logger.error("[error] malformed JSON request body (#{env['REQUEST_METHOD']} #{request.path})")
    [400, { "content-type" => "application/json" }, ['{"error":"bad_request"}']]
  end
end
