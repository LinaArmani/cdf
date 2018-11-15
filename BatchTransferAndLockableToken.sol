pragma solidity ^0.4.18;

contract Ownable {
    address public owner;

    constructor() public {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }
}

contract Pausable is Ownable {
    event Pause();
    event Unpause();
    event BatchTransferEnabled();
    event BatchTransferDisabled();

    bool public paused = false;
    bool public isBatchTransferEnabled = true;

    modifier whenBatchTransferDisabled() {
        require(!isBatchTransferEnabled);
        _;
    }

    modifier whenBatchTransferEnabled() {
        require(isBatchTransferEnabled);
        _;
    }

    function disableBatchTransfer() onlyOwner whenBatchTransferEnabled public {
        isBatchTransferEnabled = false;
        emit BatchTransferDisabled();
    }

    function enableBatchTransfer() onlyOwner whenBatchTransferDisabled public {
        isBatchTransferEnabled = true;
        emit BatchTransferEnabled();
    }

    modifier whenNotPaused() {
        require(!paused);
        _;
    }

    modifier whenPaused() {
        require(paused);
        _;
    }

    function pause() onlyOwner whenNotPaused public {
        paused = true;
        emit Pause();
    }

    function unpause() onlyOwner whenPaused public {
        paused = false;
        emit Unpause();
    }
}

library SafeMath {
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        assert(c / a == b);
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b > 0); // Solidity automatically throws when dividing by 0
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }
}

contract ERC20 {
    uint256 public totalSupply;
    function balanceOf(address who) public view returns (uint256);
    function transfer(address to, uint256 value) public returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    function allowance(address owner, address spender) public view returns (uint256);
    function transferFrom(address from, address to, uint256 value) public returns (bool);
    function approve(address spender, uint256 value) public returns (bool);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract BatchTransferAndLockableToken is Pausable, ERC20 {
    using SafeMath for uint256;
    event BatchTransfer(address indexed owner, bool value);
    event Locked(address indexed owner, uint256 value);
    event Unlocked(address indexed owner, uint256 value);
    event Mint(address indexed owner, uint value);
    event Burn(address indexed owner, uint value);

    string public name;
    string public symbol;
    uint8 public decimals;

    bool private mintable;
    bool private burnable;
    mapping (address => uint256) private balances;
    mapping (address => mapping (address => uint256)) internal allowed;
    mapping (address => bool) private allowedBatchTransfers;
    mapping (address => uint256) private lockedBalances;

    constructor(string _name, string _symbol, uint8 _decimals, uint256 _totalSupply, bool _mintable, bool _burnable) public {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        totalSupply = _totalSupply * 10 ** uint256(decimals);
        mintable = _mintable;
        burnable = _burnable;
        balances[msg.sender] = totalSupply;
        allowedBatchTransfers[msg.sender] = true;
    }

    function getMintable() public view returns (bool) {
        return mintable;
    }

    function getBurnable() public view returns (bool) {
        return burnable;
    }

    function setBatchTransfer(address _address, bool _value) public onlyOwner returns (bool) {
        allowedBatchTransfers[_address] = _value;
        emit BatchTransfer(_address, _value);
        return true;
    }

    function getBatchTransfer(address _address) public onlyOwner view returns (bool) {
        return allowedBatchTransfers[_address];
    }

    function transfer(address _to, uint256 _value) whenNotPaused public returns (bool) {
        require(_to != address(0));
        require(_value <= (balances[msg.sender] - lockedBalances[msg.sender]));

        balances[msg.sender] = balances[msg.sender].sub(_value);
        balances[_to] = balances[_to].add(_value);
        emit Transfer(msg.sender, _to, _value);
        return true;
    }

    function airdrop(address[] _funds, uint256 _amount) public whenNotPaused whenBatchTransferEnabled returns (bool) {
        require(allowedBatchTransfers[msg.sender]);
        uint256 fundslen = _funds.length;
        require(fundslen > 0 && _amount > 0);

        uint256 totalAmount = _amount.mul(fundslen);
        require((balances[msg.sender] - lockedBalances[msg.sender]) >= totalAmount);
        for (uint i = 0; i < fundslen; ++i){
            balances[_funds[i]] = balances[_funds[i]].add(_amount);
            emit Transfer(msg.sender, _funds[i], _amount);
        }

        balances[msg.sender] = balances[msg.sender].sub(totalAmount);
        return true;
    }

    function batchTransfer(address[] _funds, uint256[] _amounts) public whenNotPaused whenBatchTransferEnabled returns (bool) {
        require(allowedBatchTransfers[msg.sender]);
        uint256 fundslen = _funds.length;
        uint256 amountslen = _amounts.length;
        require(fundslen == amountslen && fundslen > 0);

        uint256 totalAmount = 0;
        for (uint i = 0; i < amountslen; ++i) {
            balances[_funds[i]] = balances[_funds[i]].add(_amounts[i]);
            totalAmount = totalAmount.add(_amounts[i]);
            emit Transfer(msg.sender, _funds[i], _amounts[i]);
        }
        require((balances[msg.sender] - lockedBalances[msg.sender]) >= totalAmount);
        balances[msg.sender] = balances[msg.sender].sub(totalAmount);
        return true;
    }

    function balanceOf(address _owner) public view returns (uint256 balance) {
        return balances[_owner];
    }

    function transferFrom(address _from, address _to, uint256 _value) public whenNotPaused returns (bool) {
        require(_to != address(0));
        require(_value <= (balances[_from] - lockedBalances[_from]));
        require(_value <= allowed[_from][msg.sender]);

        balances[_from] = balances[_from].sub(_value);
        balances[_to] = balances[_to].add(_value);
        allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);
        emit Transfer(_from, _to, _value);
        return true;
    }

    function approve(address _spender, uint256 _value) public whenNotPaused returns (bool) {
        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    function allowance(address _owner, address _spender) public view returns (uint256) {
        return allowed[_owner][_spender];
    }

    function lockedBalanceOf(address who) public view returns (uint256) {
        return lockedBalances[who];
    }

    function lock(address _owner, uint256 _value) public onlyOwner {
        uint256 available = balances[_owner].sub(lockedBalances[_owner]);
        require (available >= _value);
        lockedBalances[_owner] = lockedBalances[_owner].add(_value);
        emit Locked(_owner, _value);
    }

    function unlock(address _owner, uint256 _value) public onlyOwner {
        lockedBalances[_owner] = lockedBalances[_owner].sub(_value);
        emit Unlocked(_owner, _value);
    }

    function batchLock(address[] _holders, uint256[] _amounts) public onlyOwner {
        uint256 holdersLen = _holders.length;
        uint256 amountslen = _amounts.length;
        require(holdersLen == amountslen && holdersLen > 0);

        for (uint i = 0; i < amountslen; ++i) {
            lock(_holders[i], _amounts[i]);
        }
    }

    function batchUnlock(address[] _holders, uint256[] _amounts) public onlyOwner {
        uint256 holdersLen = _holders.length;
        uint256 amountslen = _amounts.length;
        require(holdersLen == amountslen && holdersLen > 0);

        for (uint i = 0; i < amountslen; ++i) {
            unlock(_holders[i], _amounts[i]);
        }
    }

    function mint(address _user, uint _amount) public onlyOwner {
        require(mintable);
        balances[_user] = balances[_user].add(_amount);
        totalSupply = totalSupply.add(_amount);
        emit Mint(_user, _amount);
    }

    function burn(address _user, uint _amount) public onlyOwner {
        require(burnable);
        balances[_user] = balances[_user].sub(_amount);
        totalSupply = totalSupply.sub(_amount);
        emit Burn(_user, _amount);
    }
}