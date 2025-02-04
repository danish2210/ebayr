module Ebayr # :nodoc:
  # Encapsulates a request which is sent to the eBay Trading API.
  class Request
    include Ebayr

    attr_reader :command

    # Make a new call. The URI used will be that of Ebayr::uri, unless
    # overridden here (same for auth_token, site_id and compatability_level).
    def initialize(command, options = {})
      @command = self.class.camelize(command.to_s)
      @uri = options.delete(:uri) || uri
      @uri = URI.parse(@uri) unless @uri.is_a? URI
      @auth_token = (options.delete(:auth_token) || auth_token).to_s
      @custom_headers = options.delete(:headers) || {}
      @site_id = (options.delete(:site_id) || site_id).to_s
      @compatability_level = (options.delete(:compatability_level) || compatability_level).to_s
      @http_timeout = (options.delete(:http_timeout) || 60).to_i
      # Remaining options are converted and used as input to the call
      @input = options.delete(:input) || options
    end

    def input_xml
      self.class.xml(@input)
    end

    # Gets the path to which this request will be posted
    def path
      @uri.path
    end

    # Gets the headers that will be sent with this request.
    def headers
      {
        'X-EBAY-API-COMPATIBILITY-LEVEL' => @compatability_level.to_s,
        'X-EBAY-API-DEV-NAME' => dev_id.to_s,
        'X-EBAY-API-APP-NAME' => app_id.to_s,
        'X-EBAY-API-CERT-NAME' => cert_id.to_s,
        'X-EBAY-API-CALL-NAME' => @command.to_s,
        'X-EBAY-API-SITEID' => @site_id.to_s,
        'Content-Type' => 'text/xml'
      }.merge(@custom_headers)
    end

    # Gets the body of this request (which is XML)
    def body
      <<-XML
        <?xml version="1.0" encoding="utf-8"?>
        <#{@command}Request xmlns="urn:ebay:apis:eBLBaseComponents">
          #{requester_credentials_xml}
          #{input_xml}
        </#{@command}Request>
      XML
    end

    # Returns eBay requester credential XML if @auth_token is present
    def requester_credentials_xml
      return '' unless @auth_token.present? && @custom_headers.empty?

      <<-XML
      <RequesterCredentials>
        <eBayAuthToken>#{@auth_token}</eBayAuthToken>
      </RequesterCredentials>
      XML
    end

    # Makes a HTTP connection and sends the request, returning an
    # Ebayr::Response
    def send
      http = Net::HTTP.new(@uri.host, @uri.port)
      http.read_timeout = @http_timeout

      # Output request XML if debug flag is set
      puts body if debug == true

      if @uri.port == 443
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end

      post = Net::HTTP::Post.new(@uri.path, headers)
      post.body = body

      response = http.start { |conn| conn.request(post) }

      @response = Response.new(self, response)
    end

    def to_s
      "#{@command}[#{@input}] <#{@uri}>"
    end

    # A very, very simple XML serializer.
    #
    #     Ebayr.xml("Hello!")       # => "Hello!"
    #     Ebayr.xml(:foo=>"Bar")  # => <foo>Bar</foo>
    #     Ebayr.xml(:foo=>["Bar","Baz"])  # => <foo>Bar</foo>
    def self.xml(*args)
      args.map do |structure|
        case structure
        when Hash then serialize_hash(structure)
        when Array then structure.map { |v| xml(v) }.join
        else serialize_input(structure).to_s
        end
      end.join
    end

    def self.serialize_hash(hash)
      hash.map do |k, v|
        if v.instance_of?(Array)
          v.map { |v_item| "<#{k}>#{xml(v_item)}</#{k}>" }
        elsif v.is_a?(Hash) && v.key?(:value) && v.key?(:attr)
          serialize_hash_with_attr(k, v)
        else
          "<#{k}>#{xml(v)}</#{k}>"
        end
      end.join
    end

    # Converts a hash with attributes to a tag
    # {:foo=>{:value=>"Bar", :attr=>{:name=>"baz"}}}
    # gives <foo name="baz">Bar</foo>
    def self.serialize_hash_with_attr(key, value)
      attr = value[:attr].map { |k_attr, v_attr| "#{k_attr}=\"#{v_attr}\"" }.join
      "<#{key} #{attr}>#{xml(value[:value])}</#{key}>"
    end

    # Prepares an argument for input to an eBay Trading API XML call.
    # * Times are converted to ISO 8601 format
    def self.serialize_input(input)
      case input
      when Time then input.to_time.utc.iso8601
      else input
      end
    end

    # Converts a command like get_ebay_offical_time to GeteBayOfficialTime
    def self.camelize(string)
      string = string.to_s
      return string unless string == string.downcase

      string.split('_').map(&:capitalize).join.gsub('Ebay', 'eBay')
    end

    # Gets a HTTP connection for this request. If you pass in a block, it will
    # be run on that HTTP connection.
    def http(&block)
      http = Net::HTTP.new(@uri.host, @uri.port)
      if @uri.port == 443
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      return http.start(&block) if block_given?

      http
    end
  end
end
