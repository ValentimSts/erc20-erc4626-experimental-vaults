# @version ^0.4.0

# @title OrangeStrategicVault
# @notice An advanced ERC4626 vault with strategic features
#
# @dev This vault extends the standard ERC4626 with:
#     - Deposit/Withdrawal Caps: Limits on how much can be deposited or withdrawn
#     - Whitelist System: Optional restriction to pre-approved addresses
#     - Emergency Mode: Circuit breaker to halt operations
#     - Multiple Fee Types: Deposit, withdrawal, management, and performance fees
#     - Yield Simulation: Testing function to simulate yield accrual

# ============ Interfaces ============

interface IERC20:
    def name() -> String[32]: view
    def symbol() -> String[8]: view
    def decimals() -> uint8: view
    def totalSupply() -> uint256: view
    def balanceOf(account: address) -> uint256: view
    def transfer(to: address, amount: uint256) -> bool: nonpayable
    def allowance(owner: address, spender: address) -> uint256: view
    def approve(spender: address, amount: uint256) -> bool: nonpayable
    def transferFrom(sender: address, to: address, amount: uint256) -> bool: nonpayable


# ============ Events ============

# ERC20 Events
event Transfer:
    sender: indexed(address)
    receiver: indexed(address)
    amount: uint256

event Approval:
    owner: indexed(address)
    spender: indexed(address)
    amount: uint256

# ERC4626 Events
event Deposit:
    sender: indexed(address)
    owner: indexed(address)
    assets: uint256
    shares: uint256

event Withdraw:
    sender: indexed(address)
    receiver: indexed(address)
    owner: indexed(address)
    assets: uint256
    shares: uint256

# Ownership Events
event OwnershipTransferred:
    previous_owner: indexed(address)
    new_owner: indexed(address)

# Fee Events
event DepositFeeUpdated:
    old_fee: uint256
    new_fee: uint256

event WithdrawalFeeUpdated:
    old_fee: uint256
    new_fee: uint256

event ManagementFeeUpdated:
    old_fee: uint256
    new_fee: uint256

event PerformanceFeeUpdated:
    old_fee: uint256
    new_fee: uint256

event FeeRecipientUpdated:
    old_recipient: address
    new_recipient: address

event FeesCollected:
    recipient: indexed(address)
    management_fee: uint256
    performance_fee: uint256

event DepositFeeCharged:
    depositor: indexed(address)
    fee_amount: uint256

event WithdrawalFeeCharged:
    withdrawer: indexed(address)
    fee_amount: uint256

# Strategic Events
event DepositCapUpdated:
    old_cap: uint256
    new_cap: uint256

event WithdrawalCapUpdated:
    old_cap: uint256
    new_cap: uint256

event WhitelistEnabled:
    enabled: bool

event WhitelistUpdated:
    account: indexed(address)
    status: bool

event EmergencyModeEnabled:
    enabled: bool

event YieldSimulated:
    amount: uint256


# ============ Constants ============

# Fee rates for the Orange Strategic Vault are all
# expressed in basis points (BPS) to allow 
# fine granularity.
#
# BP - Basis Point
# -------------------
#   1      BP = 0.01%
#   100    BP = 1%
#   10,000 BP = 100%

MAX_FEE_BPS: public(constant(uint16)) = 2000  # Max 20% fee
BPS_DENOMINATOR: public(constant(uint16)) = 10000
MIN_COLLECTION_INTERVAL: public(constant(uint256)) = 3600  # 1 hour in seconds

# Time constants
SECONDS_PER_YEAR: constant(uint256) = 365 * 24 * 3600  # 365 days


# ============ State Variables ============

# Storage layout optimized for gas efficiency.
# Variables are grouped by access patterns and packed when possible.

# ERC20 metadata
name: public(String[32])
symbol: public(String[8])
decimals: public(uint8)

# ERC20 state
totalSupply: public(uint256)
balanceOf: public(HashMap[address, uint256])
allowance: public(HashMap[address, HashMap[address, uint256]])

# ERC4626 state
asset: public(address)

# Ownership
owner: public(address)

# Fee configuration
fee_recipient: public(address)

# Fee rates are in basis points. The current 
# defined maximum fee for any category is 2000
# BPS (20%), which fits within a uint16.
deposit_fee_bps: public(uint16)
withdrawal_fee_bps: public(uint16)
management_fee_bps: public(uint16)  # Annual fee
performance_fee_bps: public(uint16)

# Fee tracking
last_fee_collection: public(uint256)
high_water_mark: public(uint256)

# Strategic features
deposit_cap: public(uint256)
withdrawal_cap: public(uint256)
whitelist_enabled: public(bool)
whitelist: public(HashMap[address, bool])
emergency_mode: public(bool)


# ============ Constructor ============

@deploy
def __init__(
    asset_: address,
    name_: String[32],
    symbol_: String[8],
    fee_recipient_: address,
    deposit_fee_bps_: uint16,
    withdrawal_fee_bps_: uint16,
    management_fee_bps_: uint16,
    performance_fee_bps_: uint16,
    deposit_cap_: uint256,
    withdrawal_cap_: uint256
):
    """
    @notice Constructor
    @param asset_ The underlying asset token
    @param name_ The name of the vault token
    @param symbol_ The symbol of the vault token
    @param fee_recipient_ The address that receives collected fees
    @param deposit_fee_bps_ Deposit fee in basis points
    @param withdrawal_fee_bps_ Withdrawal fee in basis points
    @param management_fee_bps_ Annual management fee in basis points
    @param performance_fee_bps_ Performance fee in basis points
    @param deposit_cap_ Maximum amount of assets that can be deposited
    @param withdrawal_cap_ Maximum amount of assets that can be withdrawn per transaction
    """
    assert fee_recipient_ != empty(address), "Zero address"
    assert deposit_fee_bps_ <= MAX_FEE_BPS, "Fee too high"
    assert withdrawal_fee_bps_ <= MAX_FEE_BPS, "Fee too high"
    assert management_fee_bps_ <= MAX_FEE_BPS, "Fee too high"
    assert performance_fee_bps_ <= MAX_FEE_BPS, "Fee too high"
    
    self.asset = asset_
    self.name = name_
    self.symbol = symbol_
    self.decimals = staticcall IERC20(asset_).decimals()
    
    self.owner = msg.sender
    self.fee_recipient = fee_recipient_
    self.deposit_fee_bps = deposit_fee_bps_
    self.withdrawal_fee_bps = withdrawal_fee_bps_
    self.management_fee_bps = management_fee_bps_
    self.performance_fee_bps = performance_fee_bps_
    self.last_fee_collection = block.timestamp
    
    self.deposit_cap = deposit_cap_
    self.withdrawal_cap = withdrawal_cap_
    
    log OwnershipTransferred(empty(address), msg.sender)


# ============ ERC20 Functions ============

@external
def transfer(to: address, amount: uint256) -> bool:
    """
    @notice Transfer tokens to a specified address
    @param to The address to transfer to
    @param amount The amount to be transferred
    @return True on success
    """
    assert to != empty(address), "Transfer to zero address"
    assert self.balanceOf[msg.sender] >= amount, "Insufficient balance"
    
    self.balanceOf[msg.sender] -= amount
    self.balanceOf[to] += amount
    
    log Transfer(msg.sender, to, amount)
    return True


@external
def approve(spender: address, amount: uint256) -> bool:
    """
    @notice Approve the passed address to spend the specified amount of tokens
    @param spender The address which will spend the funds
    @param amount The amount of tokens to be spent
    @return True on success
    """
    self.allowance[msg.sender][spender] = amount
    
    log Approval(msg.sender, spender, amount)
    return True


@external
def transferFrom(sender: address, to: address, amount: uint256) -> bool:
    """
    @notice Transfer tokens from one address to another
    @param sender The address which you want to send tokens from
    @param to The address which you want to transfer to
    @param amount The amount of tokens to be transferred
    @return True on success
    """
    assert to != empty(address), "Transfer to zero address"
    assert self.balanceOf[sender] >= amount, "Insufficient balance"
    assert self.allowance[sender][msg.sender] >= amount, "Insufficient allowance"
    
    self.balanceOf[sender] -= amount
    self.balanceOf[to] += amount
    self.allowance[sender][msg.sender] -= amount
    
    log Transfer(sender, to, amount)
    return True


# ============ ERC4626 View Functions ============

@view
@external
def totalAssets() -> uint256:
    """
    @notice Returns the total amount of underlying assets held by the vault
    @return Total assets
    """
    return staticcall IERC20(self.asset).balanceOf(self)


@view
@internal
def _total_assets() -> uint256:
    """
    @notice Internal function to get total assets
    """
    return staticcall IERC20(self.asset).balanceOf(self)


@view
@internal
def _convert_to_shares(assets: uint256, rounding_up: bool) -> uint256:
    """
    @notice Internal function to convert assets to shares
    @param assets Amount of assets
    @param rounding_up Whether to round up
    @return Equivalent shares
    """
    supply: uint256 = self.totalSupply
    total: uint256 = self._total_assets()
    
    if supply == 0 or total == 0:
        return assets
    
    if rounding_up:
        # Ceiling division: (a + b - 1) / b
        return (assets * supply + total - 1) // total
    else:
        return assets * supply // total


@view
@internal
def _convert_to_assets(shares: uint256, rounding_up: bool) -> uint256:
    """
    @notice Internal function to convert shares to assets
    @param shares Amount of shares
    @param rounding_up Whether to round up
    @return Equivalent assets
    """
    supply: uint256 = self.totalSupply
    total: uint256 = self._total_assets()
    
    if supply == 0:
        return shares
    
    if rounding_up:
        # Ceiling division: (a + b - 1) / b
        return (shares * total + supply - 1) // supply
    else:
        return shares * total // supply


@view
@external
def convertToShares(assets: uint256) -> uint256:
    """
    @notice Returns the amount of shares that would be exchanged for the given assets
    @param assets Amount of assets
    @return Equivalent shares
    """
    return self._convert_to_shares(assets, False)


@view
@external
def convertToAssets(shares: uint256) -> uint256:
    """
    @notice Returns the amount of assets that would be exchanged for the given shares
    @param shares Amount of shares
    @return Equivalent assets
    """
    return self._convert_to_assets(shares, False)


@view
@external
def maxDeposit(receiver: address) -> uint256:
    """
    @notice Returns the maximum amount of assets that can be deposited
    @param receiver The address receiving shares
    @return Maximum deposit amount
    """
    # Check emergency mode
    if self.emergency_mode:
        return 0
    
    # Check whitelist
    if self.whitelist_enabled and not self.whitelist[receiver]:
        return 0
    
    # Check deposit cap
    _deposit_cap: uint256 = self.deposit_cap
    if _deposit_cap == 0:
        return max_value(uint256)
    
    current_assets: uint256 = self._total_assets()
    if current_assets >= _deposit_cap:
        return 0
    
    return _deposit_cap - current_assets


@view
@external
def maxMint(receiver: address) -> uint256:
    """
    @notice Returns the maximum amount of shares that can be minted
    @param receiver The address receiving shares
    @return Maximum mint amount
    """
    # Check emergency mode
    if self.emergency_mode:
        return 0
    
    # Check whitelist
    if self.whitelist_enabled and not self.whitelist[receiver]:
        return 0
    
    # Check deposit cap
    _deposit_cap: uint256 = self.deposit_cap
    if _deposit_cap == 0:
        return max_value(uint256)
    
    current_assets: uint256 = self._total_assets()
    if current_assets >= _deposit_cap:
        return 0
    
    return self._convert_to_shares(_deposit_cap - current_assets, False)


@view
@external
def maxWithdraw(owner_addr: address) -> uint256:
    """
    @notice Returns the maximum amount of assets that can be withdrawn
    @param owner_addr The owner of shares
    @return Maximum withdrawal amount
    """
    # Check emergency mode (allow withdrawals in emergency mode!)
    owner_assets: uint256 = self._convert_to_assets(self.balanceOf[owner_addr], False)
    
    # Check withdrawal cap
    _withdrawal_cap: uint256 = self.withdrawal_cap
    if _withdrawal_cap == 0:
        return owner_assets
    
    if owner_assets < _withdrawal_cap:
        return owner_assets
    else:
        return _withdrawal_cap


@view
@external
def maxRedeem(owner_addr: address) -> uint256:
    """
    @notice Returns the maximum amount of shares that can be redeemed
    @param owner_addr The owner of shares
    @return Maximum redeem amount
    """
    owner_shares: uint256 = self.balanceOf[owner_addr]
    
    # Check withdrawal cap
    _withdrawal_cap: uint256 = self.withdrawal_cap
    if _withdrawal_cap == 0:
        return owner_shares
    
    max_shares: uint256 = self._convert_to_shares(_withdrawal_cap, False)
    if owner_shares < max_shares:
        return owner_shares
    else:
        return max_shares


@view
@external
def previewDeposit(assets: uint256) -> uint256:
    """
    @notice Preview deposit accounting for fees
    @param assets Amount of assets to deposit
    @return Shares that would be received
    """
    fee_amount: uint256 = assets * convert(self.deposit_fee_bps, uint256) // convert(BPS_DENOMINATOR, uint256)
    assets_after_fee: uint256 = assets - fee_amount
    return self._convert_to_shares(assets_after_fee, False)


@view
@external
def previewMint(shares: uint256) -> uint256:
    """
    @notice Preview mint accounting for fees
    @param shares Amount of shares to mint
    @return Assets required
    """
    assets: uint256 = self._convert_to_assets(shares, True)
    # Need to account for fee: assets / (1 - fee) = assets * BPS / (BPS - feeBps)
    bps: uint256 = convert(BPS_DENOMINATOR, uint256)
    fee_bps: uint256 = convert(self.deposit_fee_bps, uint256)
    return assets * bps // (bps - fee_bps)


@view
@external
def previewWithdraw(assets: uint256) -> uint256:
    """
    @notice Preview withdraw accounting for fees
    @param assets Amount of assets to withdraw
    @return Shares that would be burned
    """
    # Need to account for fee: we need more assets to end up with desired amount
    bps: uint256 = convert(BPS_DENOMINATOR, uint256)
    fee_bps: uint256 = convert(self.withdrawal_fee_bps, uint256)
    assets_before_fee: uint256 = assets * bps // (bps - fee_bps)
    return self._convert_to_shares(assets_before_fee, True)


@view
@external
def previewRedeem(shares: uint256) -> uint256:
    """
    @notice Preview redeem accounting for fees
    @param shares Amount of shares to redeem
    @return Assets that would be received
    """
    assets: uint256 = self._convert_to_assets(shares, False)
    fee_amount: uint256 = assets * convert(self.withdrawal_fee_bps, uint256) // convert(BPS_DENOMINATOR, uint256)
    return assets - fee_amount


# ============ ERC4626 Mutative Functions ============

@external
def deposit(assets: uint256, receiver: address) -> uint256:
    """
    @notice Deposits assets and mints shares to receiver
    @param assets Amount of assets to deposit
    @param receiver Address receiving shares
    @return Amount of shares minted
    """
    # Check emergency mode
    assert not self.emergency_mode, "Emergency mode"
    
    # Check whitelist
    if self.whitelist_enabled:
        assert self.whitelist[receiver], "Not whitelisted"
    
    # Check deposit cap
    _deposit_cap: uint256 = self.deposit_cap
    if _deposit_cap != 0:
        assert self._total_assets() + assets <= _deposit_cap, "Deposit cap exceeded"
    
    # Collect pending fees first
    self._collect_fees()
    
    # Cache storage read
    _deposit_fee_bps: uint256 = convert(self.deposit_fee_bps, uint256)
    _bps: uint256 = convert(BPS_DENOMINATOR, uint256)
    
    # Calculate and deduct deposit fee
    fee_amount: uint256 = assets * _deposit_fee_bps // _bps
    assets_after_fee: uint256 = assets - fee_amount
    
    # Calculate shares directly (without fee recalculation)
    shares_after_fee: uint256 = self._convert_to_shares(assets_after_fee, False)
    
    # Transfer total assets from caller
    extcall IERC20(self.asset).transferFrom(msg.sender, self, assets)
    
    # Transfer fee to recipient
    if fee_amount != 0:
        extcall IERC20(self.asset).transfer(self.fee_recipient, fee_amount)
        log DepositFeeCharged(msg.sender, fee_amount)
    
    # Mint shares based on assets after fee
    self.balanceOf[receiver] += shares_after_fee
    self.totalSupply += shares_after_fee
    
    log Transfer(empty(address), receiver, shares_after_fee)
    log Deposit(msg.sender, receiver, assets_after_fee, shares_after_fee)
    
    return shares_after_fee


@external
def mint(shares: uint256, receiver: address) -> uint256:
    """
    @notice Mints exact amount of shares to receiver
    @param shares Amount of shares to mint
    @param receiver Address receiving shares
    @return Amount of assets deposited
    """
    # Check emergency mode
    assert not self.emergency_mode, "Emergency mode"
    
    # Check whitelist
    if self.whitelist_enabled:
        assert self.whitelist[receiver], "Not whitelisted"
    
    # Collect pending fees first
    self._collect_fees()
    
    # Calculate required assets (including fee)
    assets_needed: uint256 = self._convert_to_assets(shares, True)
    bps: uint256 = convert(BPS_DENOMINATOR, uint256)
    fee_bps: uint256 = convert(self.deposit_fee_bps, uint256)
    total_assets_val: uint256 = assets_needed * bps // (bps - fee_bps)
    
    # Check deposit cap
    _deposit_cap: uint256 = self.deposit_cap
    if _deposit_cap != 0:
        assert self._total_assets() + total_assets_val <= _deposit_cap, "Deposit cap exceeded"
    
    fee_amount: uint256 = total_assets_val - assets_needed
    
    # Transfer total assets from caller
    extcall IERC20(self.asset).transferFrom(msg.sender, self, total_assets_val)
    
    # Transfer fee to recipient
    if fee_amount != 0:
        extcall IERC20(self.asset).transfer(self.fee_recipient, fee_amount)
        log DepositFeeCharged(msg.sender, fee_amount)
    
    # Mint shares
    self.balanceOf[receiver] += shares
    self.totalSupply += shares
    
    log Transfer(empty(address), receiver, shares)
    log Deposit(msg.sender, receiver, assets_needed, shares)
    
    return total_assets_val


@external
def withdraw(assets: uint256, receiver: address, owner_addr: address) -> uint256:
    """
    @notice Withdraws assets from the vault
    @param assets Amount of assets to withdraw
    @param receiver Address receiving assets
    @param owner_addr Owner of shares to burn
    @return Amount of shares burned
    """
    # Check withdrawal cap (emergency mode allows withdrawals)
    _withdrawal_cap: uint256 = self.withdrawal_cap
    if _withdrawal_cap != 0:
        assert assets <= _withdrawal_cap, "Withdrawal cap exceeded"
    
    # Collect pending fees first (skip if emergency mode)
    if not self.emergency_mode:
        self._collect_fees()
    
    # Calculate shares needed (accounting for fee)
    bps: uint256 = convert(BPS_DENOMINATOR, uint256)
    fee_bps: uint256 = convert(self.withdrawal_fee_bps, uint256)
    assets_before_fee: uint256 = assets * bps // (bps - fee_bps)
    shares: uint256 = self._convert_to_shares(assets_before_fee, True)
    
    # Check allowance if caller is not owner
    if msg.sender != owner_addr:
        assert self.allowance[owner_addr][msg.sender] >= shares, "Insufficient allowance"
        self.allowance[owner_addr][msg.sender] -= shares
    
    # Burn shares
    assert self.balanceOf[owner_addr] >= shares, "Insufficient balance"
    self.balanceOf[owner_addr] -= shares
    self.totalSupply -= shares
    
    log Transfer(owner_addr, empty(address), shares)
    
    # Calculate withdrawal fee
    fee_amount: uint256 = assets_before_fee * fee_bps // bps
    
    # Transfer fee to recipient
    if fee_amount != 0:
        extcall IERC20(self.asset).transfer(self.fee_recipient, fee_amount)
        log WithdrawalFeeCharged(owner_addr, fee_amount)
    
    # Transfer remaining assets to receiver
    extcall IERC20(self.asset).transfer(receiver, assets)
    
    log Withdraw(msg.sender, receiver, owner_addr, assets, shares)
    
    return shares


@external
def redeem(shares: uint256, receiver: address, owner_addr: address) -> uint256:
    """
    @notice Redeems shares for assets
    @param shares Amount of shares to redeem
    @param receiver Address receiving assets
    @param owner_addr Owner of shares to burn
    @return Amount of assets received
    """
    # Check allowance if caller is not owner
    if msg.sender != owner_addr:
        assert self.allowance[owner_addr][msg.sender] >= shares, "Insufficient allowance"
        self.allowance[owner_addr][msg.sender] -= shares
    
    # Collect pending fees first (skip if emergency mode)
    if not self.emergency_mode:
        self._collect_fees()
    
    # Burn shares
    assert self.balanceOf[owner_addr] >= shares, "Insufficient balance"
    self.balanceOf[owner_addr] -= shares
    self.totalSupply -= shares
    
    log Transfer(owner_addr, empty(address), shares)
    
    # Convert shares to assets
    assets: uint256 = self._convert_to_assets(shares, False)
    
    # Check withdrawal cap
    _withdrawal_cap: uint256 = self.withdrawal_cap
    if _withdrawal_cap != 0:
        assert assets <= _withdrawal_cap, "Withdrawal cap exceeded"
    
    # Calculate withdrawal fee
    bps: uint256 = convert(BPS_DENOMINATOR, uint256)
    fee_bps: uint256 = convert(self.withdrawal_fee_bps, uint256)
    fee_amount: uint256 = assets * fee_bps // bps
    assets_after_fee: uint256 = assets - fee_amount
    
    # Transfer fee to recipient
    if fee_amount != 0:
        extcall IERC20(self.asset).transfer(self.fee_recipient, fee_amount)
        log WithdrawalFeeCharged(owner_addr, fee_amount)
    
    # Transfer remaining assets to receiver
    extcall IERC20(self.asset).transfer(receiver, assets_after_fee)
    
    log Withdraw(msg.sender, receiver, owner_addr, assets_after_fee, shares)
    
    return assets_after_fee


# ============ Fee Management Functions ============

@external
def setDepositFee(new_fee_bps: uint16):
    """
    @notice Sets the deposit fee to a new value
    @param new_fee_bps New deposit fee in basis points
    """
    assert msg.sender == self.owner, "Only owner"
    assert new_fee_bps <= MAX_FEE_BPS, "Fee too high"
    
    log DepositFeeUpdated(convert(self.deposit_fee_bps, uint256), convert(new_fee_bps, uint256))
    self.deposit_fee_bps = new_fee_bps


@external
def setWithdrawalFee(new_fee_bps: uint16):
    """
    @notice Sets the withdrawal fee to a new value
    @param new_fee_bps New withdrawal fee in basis points
    """
    assert msg.sender == self.owner, "Only owner"
    assert new_fee_bps <= MAX_FEE_BPS, "Fee too high"
    
    log WithdrawalFeeUpdated(convert(self.withdrawal_fee_bps, uint256), convert(new_fee_bps, uint256))
    self.withdrawal_fee_bps = new_fee_bps


@external
def setManagementFee(new_fee_bps: uint16):
    """
    @notice Sets the management fee to a new value
    @param new_fee_bps New management fee in basis points
    """
    assert msg.sender == self.owner, "Only owner"
    assert new_fee_bps <= MAX_FEE_BPS, "Fee too high"
    
    # Collect pending fees before changing rate
    self._collect_fees()
    
    log ManagementFeeUpdated(convert(self.management_fee_bps, uint256), convert(new_fee_bps, uint256))
    self.management_fee_bps = new_fee_bps


@external
def setPerformanceFee(new_fee_bps: uint16):
    """
    @notice Sets the performance fee to a new value
    @param new_fee_bps New performance fee in basis points
    """
    assert msg.sender == self.owner, "Only owner"
    assert new_fee_bps <= MAX_FEE_BPS, "Fee too high"
    
    # Collect pending fees before changing rate
    self._collect_fees()
    
    log PerformanceFeeUpdated(convert(self.performance_fee_bps, uint256), convert(new_fee_bps, uint256))
    self.performance_fee_bps = new_fee_bps


@external
def setFeeRecipient(new_recipient: address):
    """
    @notice Sets the fee recipient address to a new value
    @param new_recipient New fee recipient address
    """
    assert msg.sender == self.owner, "Only owner"
    assert new_recipient != empty(address), "Zero address"
    
    log FeeRecipientUpdated(self.fee_recipient, new_recipient)
    self.fee_recipient = new_recipient


@internal
def _collect_fees():
    """
    @notice Internal function to collect accrued management and performance fees
    """
    _last_fee_collection: uint256 = self.last_fee_collection
    
    # Skip if collected recently (gas optimization)
    if block.timestamp <= _last_fee_collection:
        return
    if block.timestamp - _last_fee_collection < MIN_COLLECTION_INTERVAL:
        return
    
    current_assets: uint256 = self._total_assets()
    total_shares: uint256 = self.totalSupply
    
    if total_shares == 0 or current_assets == 0:
        self.last_fee_collection = block.timestamp
        return
    
    management_fee_amount: uint256 = 0
    performance_fee_amount: uint256 = 0
    
    # Cache storage reads
    _management_fee_bps: uint256 = convert(self.management_fee_bps, uint256)
    _performance_fee_bps: uint256 = convert(self.performance_fee_bps, uint256)
    _high_water_mark: uint256 = self.high_water_mark
    _bps: uint256 = convert(BPS_DENOMINATOR, uint256)
    
    # Calculate management fee (pro-rated for time elapsed)
    time_elapsed: uint256 = block.timestamp - _last_fee_collection
    if time_elapsed != 0 and _management_fee_bps != 0:
        numerator: uint256 = _management_fee_bps * time_elapsed
        denominator: uint256 = SECONDS_PER_YEAR * _bps
        management_fee_amount = current_assets * numerator // denominator
    
    # Calculate performance fee (on profit above high-water mark)
    current_share_value: uint256 = current_assets * 10 ** 18 // total_shares
    if current_share_value > _high_water_mark and _performance_fee_bps != 0:
        profit: uint256 = (current_share_value - _high_water_mark) * total_shares // 10 ** 18
        performance_fee_amount = profit * _performance_fee_bps // _bps
        self.high_water_mark = current_share_value
    
    total_fee_assets: uint256 = management_fee_amount + performance_fee_amount
    
    if total_fee_assets != 0:
        # Convert fee assets to shares and mint to fee recipient
        fee_shares: uint256 = self._convert_to_shares(total_fee_assets, False)
        if fee_shares != 0:
            self.balanceOf[self.fee_recipient] += fee_shares
            self.totalSupply += fee_shares
            log Transfer(empty(address), self.fee_recipient, fee_shares)
            log FeesCollected(self.fee_recipient, management_fee_amount, performance_fee_amount)
    
    self.last_fee_collection = block.timestamp


@external
def collectFees():
    """
    @notice Collects accrued management and performance fees
    """
    self._collect_fees()


# ============ Strategic Functions ============

@external
def setDepositCap(new_cap: uint256):
    """
    @notice Sets the deposit cap
    @param new_cap New deposit cap (0 = unlimited)
    """
    assert msg.sender == self.owner, "Only owner"
    
    log DepositCapUpdated(self.deposit_cap, new_cap)
    self.deposit_cap = new_cap


@external
def setWithdrawalCap(new_cap: uint256):
    """
    @notice Sets the withdrawal cap
    @param new_cap New withdrawal cap (0 = unlimited)
    """
    assert msg.sender == self.owner, "Only owner"
    
    log WithdrawalCapUpdated(self.withdrawal_cap, new_cap)
    self.withdrawal_cap = new_cap


@external
def setWhitelistEnabled(enabled: bool):
    """
    @notice Enables or disables the whitelist
    @param enabled Whether whitelist is enabled
    """
    assert msg.sender == self.owner, "Only owner"
    
    self.whitelist_enabled = enabled
    log WhitelistEnabled(enabled)


@external
def updateWhitelist(account: address, status: bool):
    """
    @notice Updates whitelist status for an account
    @param account Address to update
    @param status Whether the account is whitelisted
    """
    assert msg.sender == self.owner, "Only owner"
    
    self.whitelist[account] = status
    log WhitelistUpdated(account, status)


@external
def setEmergencyMode(enabled: bool):
    """
    @notice Enables or disables emergency mode
    @dev In emergency mode, deposits are halted but withdrawals are allowed
    @param enabled Whether emergency mode is enabled
    """
    assert msg.sender == self.owner, "Only owner"
    
    self.emergency_mode = enabled
    log EmergencyModeEnabled(enabled)


@external
def simulateYield(amount: uint256):
    """
    @notice Simulates yield by transferring assets to the vault
    @dev This is for testing purposes only
    @param amount Amount of assets to add as yield
    """
    extcall IERC20(self.asset).transferFrom(msg.sender, self, amount)
    log YieldSimulated(amount)


# ============ View Functions ============

@view
@external
def getFeeRates() -> (uint256, uint256, uint256, uint256):
    """
    @notice Get all fee rates
    @return Tuple of (deposit, withdrawal, management, performance) fees in basis points
    """
    return (
        convert(self.deposit_fee_bps, uint256),
        convert(self.withdrawal_fee_bps, uint256),
        convert(self.management_fee_bps, uint256),
        convert(self.performance_fee_bps, uint256)
    )


@view
@external
def getPendingManagementFee() -> uint256:
    """
    @notice Get pending management fee amount
    @return Pending management fee in assets
    """
    current_assets: uint256 = self._total_assets()
    _management_fee_bps: uint256 = convert(self.management_fee_bps, uint256)
    _last_fee_collection: uint256 = self.last_fee_collection
    _bps: uint256 = convert(BPS_DENOMINATOR, uint256)
    
    if block.timestamp <= _last_fee_collection or _management_fee_bps == 0 or current_assets == 0:
        return 0
    
    time_elapsed: uint256 = block.timestamp - _last_fee_collection
    numerator: uint256 = _management_fee_bps * time_elapsed
    denominator: uint256 = SECONDS_PER_YEAR * _bps
    return current_assets * numerator // denominator


@view
@external
def shareValue() -> uint256:
    """
    @notice Get current share value (price per share)
    @return Share value scaled by 1e18
    """
    total_shares: uint256 = self.totalSupply
    if total_shares == 0:
        return 10 ** 18
    return self._total_assets() * 10 ** 18 // total_shares


@view
@external
def isWhitelisted(account: address) -> bool:
    """
    @notice Check if an account is whitelisted
    @param account Address to check
    @return True if whitelisted
    """
    return self.whitelist[account]


@view
@external
def getStrategicParams() -> (uint256, uint256, bool, bool):
    """
    @notice Get strategic parameters
    @return Tuple of (deposit_cap, withdrawal_cap, whitelist_enabled, emergency_mode)
    """
    return (
        self.deposit_cap,
        self.withdrawal_cap,
        self.whitelist_enabled,
        self.emergency_mode
    )


# ============ Ownership Functions ============

@external
def transferOwnership(new_owner: address):
    """
    @notice Transfers ownership of the contract to a new account
    @param new_owner The address of the new owner
    """
    assert msg.sender == self.owner, "Only owner"
    assert new_owner != empty(address), "New owner is zero address"
    
    old_owner: address = self.owner
    self.owner = new_owner
    
    log OwnershipTransferred(old_owner, new_owner)
