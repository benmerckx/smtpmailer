package smtpmailer;

typedef AddressData = {
	address: String,
	?displayName: String,
}

@:forward
abstract Address(AddressData) from AddressData {
	public inline function new( address: AddressData )
		this = {
			address: AddressTools.sanitizeAddress(address.address),
			displayName: address.displayName
		}

	@:from
	public static function ofString( address: String ): Address
		return new Address({ address: address });

	public function format()
		return this.displayName != null
			? '"${this.displayName}" ${this.address}'
			: '${this.address}';
}
