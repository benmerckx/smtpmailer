package smtpmailer;

import mtwin.mail.Tools;

typedef AddressData = {
	address: String,
	?displayName: String
}

@:forward(displayName)
abstract Address(AddressData) from AddressData {
	public inline function new(address)
		this = address;

	public var address(get, never): String;
	function get_address()
		return Tools.formatAddress([{
			name: null,
			address: this.address
		}]);

	@:from
	public static function ofString(address: String)
		return new Address({address: address});

	public function toString()
		return Tools.formatAddress([{
			name: this.displayName,
			address: this.address
		}]);
}
