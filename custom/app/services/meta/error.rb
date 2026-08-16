class Meta::Error < StandardError
  attr_reader :code, :error_subcode, :error_type, :raw_error

  def initialize(message = nil, code: nil, error_subcode: nil, error_type: nil, raw_error: nil)
    @code = code
    @error_subcode = error_subcode
    @error_type = error_type
    @raw_error = raw_error
    super(message)
  end
end
