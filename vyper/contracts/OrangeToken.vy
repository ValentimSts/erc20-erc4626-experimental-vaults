# @version ^0.4.0

# @title OrangeToken
# @notice ERC20 token with mint and burn capabilities.
# @dev Implements ERC20 standard with owner-only minting

# ============ Events ============

event Transfer:
    sender: indexed(address)
    receiver: indexed(address)
    amount: uint256

event Approval:
    owner: indexed(address)
    spender: indexed(address)
    amount: uint256

event OwnershipTransferred:
    previous_owner: indexed(address)
    new_owner: indexed(address)


# ============ State Variables ============

# Storage layout optimized for gas efficiency.
# --------------------------------------------
# Slot 1:
#   - owner            20 bytes
#   - decimals          1 byte
#
# Slot 2:
#   - totalSupply      32 bytes
#
# Slot 3+:
#   - balanceOf mapping
#   - allowance mapping

# ERC20 metadata
name: public(String[32])
symbol: public(String[8])
decimals: public(uint8)

# ERC20 state
totalSupply: public(uint256)
balanceOf: public(HashMap[address, uint256])
allowance: public(HashMap[address, HashMap[address, uint256]])

# Ownership
owner: public(address)


# ============ Constructor ============

@deploy
def __init__():
    """
    @notice Initializes the OrangeToken with name, symbol, and sets deployer as owner
    """
    self.name = "OrangeToken"
    self.symbol = "ORNG"
    self.decimals = 18
    self.owner = msg.sender
    
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


# ============ Mint Functions ============

@external
def mint(to: address, amount: uint256):
    """
    @notice Mints `amount` tokens to the specified address.
    @dev Only callable by the owner
    @param to The address to receive the minted tokens.
    @param amount The number of tokens to mint.
    """
    assert msg.sender == self.owner, "Only owner"
    assert to != empty(address), "Mint to zero address"
    
    self.totalSupply += amount
    self.balanceOf[to] += amount
    
    log Transfer(empty(address), to, amount)


# ============ Burn Functions ============

@external
def burn(amount: uint256):
    """
    @notice Burns `amount` tokens from the caller's balance
    @param amount The number of tokens to burn
    """
    assert self.balanceOf[msg.sender] >= amount, "Insufficient balance"
    
    self.balanceOf[msg.sender] -= amount
    self.totalSupply -= amount
    
    log Transfer(msg.sender, empty(address), amount)


@external
def burnFrom(account: address, amount: uint256):
    """
    @notice Burns `amount` tokens from the specified account using allowance
    @param account The address to burn tokens from
    @param amount The number of tokens to burn
    """
    assert self.balanceOf[account] >= amount, "Insufficient balance"
    assert self.allowance[account][msg.sender] >= amount, "Insufficient allowance"
    
    self.allowance[account][msg.sender] -= amount
    self.balanceOf[account] -= amount
    self.totalSupply -= amount
    
    log Transfer(account, empty(address), amount)


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


@external
def renounceOwnership():
    """
    @notice Leaves the contract without owner. Will not be possible to call
    `onlyOwner` functions anymore.
    """
    assert msg.sender == self.owner, "Only owner"
    
    old_owner: address = self.owner
    self.owner = empty(address)
    
    log OwnershipTransferred(old_owner, empty(address))
