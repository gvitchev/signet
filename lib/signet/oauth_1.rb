require 'addressable/uri'
require 'signet'

begin
  require 'securerandom'
rescue LoadError
  require 'compat/securerandom'
end

module Signet #:nodoc:
  module OAuth1
    OUT_OF_BAND = 'oob'

    ##
    # Converts a value to a percent-encoded <code>String</code> according to
    # the rules given in RFC 5849.  All non-unreserved characters are
    # percent-encoded.
    #
    # @param [Symbol, #to_str] value The value to be encoded.
    #
    # @return [String] The percent-encoded value.
    def self.encode(value)
      value = value.to_s if value.kind_of?(Symbol)
      return Addressable::URI.encode_component(
        value,
        Addressable::URI::CharacterClasses::UNRESERVED
      )
    end

    ##
    # Converts a percent-encoded String to an unencoded value.
    #
    # @param [#to_str] value
    #   The percent-encoded <code>String</code> to be unencoded.
    #
    # @return [String] The unencoded value.
    def self.unencode(value)
      return Addressable::URI.unencode_component(value)
    end

    ##
    # Returns a timestamp suitable for use as an <code>'oauth_timestamp'</code>
    # value.
    #
    # @return [String] The current timestamp.
    def self.generate_timestamp()
      return Time.now.to_i.to_s
    end

    ##
    # Returns a nonce suitable for use as an <code>'oauth_nonce'</code>
    # value.
    #
    # @return [String] A random nonce.
    def self.generate_nonce()
      return SecureRandom.random_bytes(16).unpack('H*').join('')
    end

    ##
    # Processes an options <code>Hash</code> to find a credential key value.
    # Allows for greater flexibility in configuration.
    #
    # @param [Symbol] credential_type
    #   One of <code>:client</code>, <code>:temporary</code>,
    #   <code>:token</code>, <code>:consumer</code>, <code>:request</code>,
    #   or <code>:access</code>.
    #
    # @return [String] The credential key value.
    def self.extract_credential_key_option(credential_type, options)
      credential_key_symbol =
        ("#{credential_type}_credential_key").to_sym
      credential_symbol =
        ("#{credential_type}_credential").to_sym
      if options[credential_key_symbol]
        credential_key = options[credential_key_symbol]
      elsif options[credential_symbol]
        require 'signet/oauth_1/credential'
        if !options[credential_symbol].respond_to?(:key)
          raise TypeError,
            "Expected Signet::OAuth1::Credential, " +
            "got #{options[credential_symbol].class}."
        end
        credential_key = options[credential_symbol].key
      elsif options[:client]
        require 'signet/oauth_1/client'
        if !options[:client].kind_of?(::Signet::OAuth1::Client)
          raise TypeError,
            "Expected Signet::OAuth1::Client, got #{options[:client].class}."
        end
        credential_key = options[:client].send(credential_key_symbol)
      else
        credential_key = nil
      end
      if credential_key != nil && !credential_key.kind_of?(String)
        raise TypeError,
          "Expected String, got #{credential_key.class}."
      end
      return credential_key
    end

    ##
    # Processes an options <code>Hash</code> to find a credential secret value.
    # Allows for greater flexibility in configuration.
    #
    # @param [Symbol] credential_type
    #   One of <code>:client</code>, <code>:temporary</code>,
    #   <code>:token</code>, <code>:consumer</code>, <code>:request</code>,
    #   or <code>:access</code>.
    #
    # @return [String] The credential secret value.
    def self.extract_credential_secret_option(credential_type, options)
      credential_secret_symbol =
        ("#{credential_type}_credential_secret").to_sym
      credential_symbol =
        ("#{credential_type}_credential").to_sym
      if options[credential_secret_symbol]
        credential_secret = options[credential_secret_symbol]
      elsif options[credential_symbol]
        require 'signet/oauth_1/credential'
        if !options[credential_symbol].respond_to?(:secret)
          raise TypeError,
            "Expected Signet::OAuth1::Credential, " +
            "got #{options[credential_symbol].class}."
        end
        credential_secret = options[credential_symbol].secret
      elsif options[:client]
        require 'signet/oauth_1/client'
        if !options[:client].kind_of?(::Signet::OAuth1::Client)
          raise TypeError,
            "Expected Signet::OAuth1::Client, got #{options[:client].class}."
        end
        credential_secret = options[:client].send(credential_secret_symbol)
      else
        credential_secret = nil
      end
      if credential_secret != nil && !credential_secret.kind_of?(String)
        raise TypeError,
          "Expected String, got #{credential_secret.class}."
      end
      return credential_secret
    end

    ##
    # Normalizes a set of OAuth parameters according to the algorithm given
    # in RFC 5849.  Sorts key/value pairs lexically by byte order, first by
    # key, then by value, joins key/value pairs with the '=' character, then
    # joins the entire parameter list with '&' characters.
    #
    # @param [Enumerable] parameters The OAuth parameter list.
    #
    # @return [String] The normalized parameter list.
    def self.normalize_parameters(parameters)
      if !parameters.kind_of?(Enumerable)
        raise TypeError, "Expected Enumerable, got #{parameters.class}."
      end
      parameter_list = parameters.map do |k, v|
        next if k == "oauth_signature"
        # This is probably the wrong place to try to exclude the realm
        "#{self.encode(k)}=#{self.encode(v)}"
      end
      return parameter_list.compact.sort.join("&")
    end

    ##
    # Generates a signature base string according to the algorithm given in
    # RFC 5849.  Joins the method, URI, and normalized parameter string with
    # '&' characters.
    #
    # @param [String] method The HTTP method.
    # @param [Addressable::URI, String, #to_str] The URI.
    # @param [Enumerable] parameters The OAuth parameter list.
    #
    # @return [String] The signature base string.
    def self.generate_base_string(method, uri, parameters)
      if !parameters.kind_of?(Enumerable)
        raise TypeError, "Expected Enumerable, got #{parameters.class}."
      end
      method = method.to_s.upcase
      parsed_uri = Addressable::URI.parse(uri)
      uri = Addressable::URI.new(
        :scheme => parsed_uri.normalized_scheme,
        :authority => parsed_uri.normalized_authority,
        :path => parsed_uri.path,
        :query => parsed_uri.query,
        :fragment => parsed_uri.fragment
      )
      uri_parameters = uri.query_values.to_a
      uri = uri.omit(:query, :fragment).to_s
      merged_parameters =
        uri_parameters.concat(parameters.map { |k, v| [k, v] })
      parameter_string = self.normalize_parameters(merged_parameters)
      return [
        self.encode(method),
        self.encode(uri),
        self.encode(parameter_string)
      ].join('&')
    end

    ##
    # Generates an <code>Authorization</code> header from a parameter list
    # according to the rules given in RFC 5849.
    #
    # @param [Enumerable] parameters The OAuth parameter list.
    # @param [String] realm
    #   The <code>Authorization</code> realm.  See RFC 2617.
    #
    # @return [String] The <code>Authorization</code> header.
    def self.generate_authorization_header(parameters, realm=nil)
      if !parameters.kind_of?(Enumerable) || parameters.kind_of?(String)
        raise TypeError, "Expected Enumerable, got #{parameters.class}."
      end
      parameter_list = parameters.map do |k, v|
        if k == 'realm'
          raise ArgumentError,
            'The "realm" parameter must be specified as a separate argument.'
        end
        "#{self.encode(k)}=\"#{self.encode(v)}\""
      end
      if realm
        realm = realm.gsub('"', '\"')
        parameter_list.unshift("realm=\"#{realm}\"")
      end
      return 'OAuth ' + parameter_list.join(", ")
    end

    ##
    # Parses an <code>Authorization</code> header into its component
    # parameters.  Parameter keys and values are decoded according to the
    # rules given in RFC 5849.
    def self.parse_authorization_header(field_value)
      if !field_value.kind_of?(String)
        raise TypeError, "Expected String, got #{field_value.class}."
      end
      auth_scheme = field_value[/^([-._0-9a-zA-Z]+)/, 1]
      case auth_scheme
      when /^OAuth$/i
        # Other token types may be supported eventually
        pairs = Signet.parse_auth_param_list(field_value[/^OAuth\s+(.*)$/i, 1])
        return (pairs.inject([]) do |accu, (k, v)|
          if k != 'realm'
            k = self.unencode(k)
            v = self.unencode(v)
          end
          accu << [k, v]
          accu
        end)
      else
        raise ParseError,
          'Parsing non-OAuth Authorization headers is out of scope.'
      end
    end

    ##
    # Parses an <code>application/x-www-form-urlencoded</code> HTTP response
    # body into an OAuth key/secret pair.
    #
    # @param [String] body The response body.
    #
    # @return [Signet::OAuth1::Credential] The OAuth credentials.
    def self.parse_form_encoded_credentials(body)
      if !body.kind_of?(String)
        raise TypeError, "Expected String, got #{body.class}."
      end
      return Signet::OAuth1::Credential.new(
        Addressable::URI.form_unencode(body)
      )
    end

    ##
    # Generates an OAuth signature using the signature method indicated in the
    # parameter list.  Unsupported signature methods will result in a
    # <code>NotImplementedError</code> exception being raised.
    #
    # @param [String] method The HTTP method.
    # @param [Addressable::URI, String, #to_str] The URI.
    # @param [Enumerable] parameters The OAuth parameter list.
    # @param [String] client_credential_secret The client credential secret.
    # @param [String] token_credential_secret
    #   The token credential secret.  Omitted when unavailable.
    #
    # @return [String] The signature.
    def self.sign_parameters(method, uri, parameters,
        client_credential_secret, token_credential_secret=nil)
      # Technically, the token_credential_secret parameter here may actually
      # be a temporary credential secret when obtaining a token credential
      # for the first time
      base_string = self.generate_base_string(method, uri, parameters)
      parameters = parameters.inject({}) { |h,(k,v)| h[k.to_s]=v; h }
      signature_method = parameters['oauth_signature_method']
      case signature_method
      when 'HMAC-SHA1'
        require 'signet/oauth_1/signature_methods/hmac_sha1'
        return Signet::OAuth1::HMACSHA1.generate_signature(
          base_string, client_credential_secret, token_credential_secret
        )
      else
        raise NotImplementedError,
          "Unsupported signature method: #{signature_method}"
      end
    end

    ##
    # Generates an OAuth parameter list to be used when obtaining a set of
    # temporary credentials.
    #
    # @param [Hash] options
    #   The configuration parameters for the request.
    #   - <code>:client_credential_key</code> —
    #     The client credential key.
    #   - <code>:callback</code> —
    #     The OAuth callback.  Defaults to {Signet::OAuth1::OUT_OF_BAND}.
    #   - <code>:signature_method</code> —
    #     The signature method.  Defaults to <code>'HMAC-SHA1'</code>.
    #   - <code>:additional_parameters</code> —
    #     Non-standard additional parameters.
    #
    # @return [Array]
    #   The parameter list as an <code>Array</code> of key/value pairs.
    def self.unsigned_temporary_credential_parameters(options={})
      options = {
        :callback => ::Signet::OAuth1::OUT_OF_BAND,
        :signature_method => 'HMAC-SHA1',
        :additional_parameters => []
      }.merge(options)
      client_credential_key =
        self.extract_credential_key_option(:client, options)
      if client_credential_key == nil
        raise ArgumentError, "Missing :client_credential_key parameter."
      end
      parameters = [
        ["oauth_consumer_key", client_credential_key],
        ["oauth_signature_method", options[:signature_method]],
        ["oauth_timestamp", self.generate_timestamp()],
        ["oauth_nonce", self.generate_nonce()],
        ["oauth_version", "1.0"],
        ["oauth_callback", options[:callback]]
      ]
      # Works for any Enumerable
      options[:additional_parameters].each do |key, value|
        parameters << [key, value]
      end
      return parameters
    end

    ##
    # Appends the optional 'oauth_token' and 'oauth_callback' parameters to
    # the base authorization URI.
    #
    # @param [Addressable::URI, String, #to_str] authorization_uri
    #   The base authorization URI.
    #
    # @return [String] The authorization URI to redirect the user to.
    def self.generate_authorization_uri(authorization_uri, options={})
      options = {
        :callback => nil,
        :additional_parameters => {}
      }.merge(options)
      temporary_credential_key =
        self.extract_credential_key_option(:temporary, options)
      parsed_uri = Addressable::URI.parse(authorization_uri).dup
      query_values = parsed_uri.query_values || {}
      if options[:additional_parameters]
        query_values = query_values.merge(
          options[:additional_parameters].inject({}) { |h,(k,v)| h[k]=v; h }
        )
      end
      if temporary_credential_key
        query_values['oauth_token'] = temporary_credential_key
      end
      if options[:callback]
        query_values['oauth_callback'] = options[:callback]
      end
      parsed_uri.query_values = query_values
      return parsed_uri.normalize.to_s
    end

    ##
    # Generates an OAuth parameter list to be used when obtaining a set of
    # token credentials.
    #
    # @param [Hash] options
    #   The configuration parameters for the request.
    #   - <code>:client_credential_key</code> —
    #     The client credential key.
    #   - <code>:temporary_credential_key</code> —
    #     The temporary credential key.
    #   - <code>:verifier</code> —
    #     The OAuth verifier.
    #   - <code>:signature_method</code> —
    #     The signature method.  Defaults to <code>'HMAC-SHA1'</code>.
    #
    # @return [Array]
    #   The parameter list as an <code>Array</code> of key/value pairs.
    def self.unsigned_token_credential_parameters(options={})
      options = {
        :signature_method => 'HMAC-SHA1',
        :verifier => nil
      }.merge(options)
      client_credential_key =
        self.extract_credential_key_option(:client, options)
      temporary_credential_key =
        self.extract_credential_key_option(:temporary, options)
      if client_credential_key == nil
        raise ArgumentError, "Missing :client_credential_key parameter."
      end
      if temporary_credential_key == nil
        raise ArgumentError, "Missing :temporary_credential_key parameter."
      end
      if options[:verifier] == nil
        raise ArgumentError, "Missing :verifier parameter."
      end
      parameters = [
        ["oauth_consumer_key", client_credential_key],
        ["oauth_token", temporary_credential_key],
        ["oauth_signature_method", options[:signature_method]],
        ["oauth_timestamp", self.generate_timestamp()],
        ["oauth_nonce", self.generate_nonce()],
        ["oauth_verifier", options[:verifier]],
        ["oauth_version", "1.0"]
      ]
      # No additional parameters allowed here
      return parameters
    end

    ##
    # Generates an OAuth parameter list to be used when requesting a
    # protected resource.
    #
    # @param [Hash] options
    #   The configuration parameters for the request.
    #   - <code>:client_credential_key</code> —
    #     The client credential key.
    #   - <code>:token_credential_key</code> —
    #     The token credential key.
    #   - <code>:signature_method</code> —
    #     The signature method.  Defaults to <code>'HMAC-SHA1'</code>.
    #   - <code>:two_legged</code> —
    #     A switch for two-legged OAuth.  Defaults to <code>false</code>.
    #
    # @return [Array]
    #   The parameter list as an <code>Array</code> of key/value pairs.
    def self.unsigned_resource_parameters(options={})
      options = {
        :signature_method => 'HMAC-SHA1',
        :two_legged => false
      }.merge(options)
      client_credential_key =
        self.extract_credential_key_option(:client, options)
      if client_credential_key == nil
        raise ArgumentError, "Missing :client_credential_key parameter."
      end
      unless options[:two_legged]
        token_credential_key =
          self.extract_credential_key_option(:token, options)
        if token_credential_key == nil
          raise ArgumentError, "Missing :token_credential_key parameter."
        end
      end
      parameters = [
        ["oauth_consumer_key", client_credential_key],
        ["oauth_signature_method", options[:signature_method]],
        ["oauth_timestamp", self.generate_timestamp()],
        ["oauth_nonce", self.generate_nonce()],
        ["oauth_version", "1.0"]
      ]
      unless options[:two_legged]
        parameters << ["oauth_token", token_credential_key]
      end
      # No additional parameters allowed here
      return parameters
    end
  end
end
