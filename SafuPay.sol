// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
}

contract SafeTransfer {
    struct Transfer {
        address sender_address;
        address token_address;
        uint256 amount;
        bool is_claimed;
        bool is_cancelled;
    }
    
    Transfer[] public transfers;
    
    mapping(address => uint256[]) public sender_indexes;
    mapping(bytes32 => uint256) public receiver_hash_index;
    
    event Deposited(uint256 indexed index, address indexed sender, address token, uint256 amount, bytes32 receiver_hash);
    event Claimed(uint256 indexed index, address indexed receiver, uint256 amount);
    event Cancelled(uint256 indexed index, address indexed sender, uint256 amount);
    
    function deposit(address token_address, bytes32 receiver_hash, uint256 amount) external {
        require(receiver_hash_index[receiver_hash] == 0, "Receiver hash already used");
        
        IERC20 token = IERC20(token_address);
        uint256 balanceBefore = token.balanceOf(address(this));
        
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        uint256 balanceAfter = token.balanceOf(address(this));
        require(balanceAfter - balanceBefore >= amount, "Balance check failed");
        
        Transfer memory newTransfer = Transfer({
            sender_address: msg.sender,
            token_address: token_address,
            amount: amount,
            is_claimed: false,
            is_cancelled: false
        });
        
        transfers.push(newTransfer);
        uint256 newIndex = transfers.length - 1;
        
        sender_indexes[msg.sender].push(newIndex);
        receiver_hash_index[receiver_hash] = newIndex;
        
        emit Deposited(newIndex, msg.sender, token_address, amount, receiver_hash);
    }
    
    function get_receiver_hash(bytes32 salt_hash, address receiver_address) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(salt_hash, receiver_address));
    }
    
    function claim(bytes32 salt_hash) external {
        bytes32 receiver_hash = get_receiver_hash(salt_hash, msg.sender);
        uint256 index = receiver_hash_index[receiver_hash];

        Transfer storage transferData = transfers[index];
        
        require(!transferData.is_claimed, "Already claimed");
        require(!transferData.is_cancelled, "Transfer cancelled");
        
        transferData.is_claimed = true;
        
        IERC20 token = IERC20(transferData.token_address);
        require(token.transfer(msg.sender, transferData.amount), "Transfer failed");
        
        emit Claimed(index, msg.sender, transferData.amount);
    }
    
    function cancel(uint256 index) external {
        Transfer storage transferData = transfers[index];
        
        require(!transferData.is_claimed, "Already claimed");
        require(!transferData.is_cancelled, "Already cancelled");
        require(transferData.sender_address == msg.sender, "Not the sender");
        
        transferData.is_cancelled = true;
        
        IERC20 token = IERC20(transferData.token_address);
        require(token.transfer(msg.sender, transferData.amount), "Transfer failed");
        
        emit Cancelled(index, msg.sender, transferData.amount);
    }
    
    function getSenderTransfersLength(address sender) external view returns (uint256) {
        return sender_indexes[sender].length;
    }

    function getSenderTransfersByOffset(
        address sender,
        uint256 offset,
        uint256 limit
    ) external view returns (uint256[] memory) {
        uint256[] storage senderTransferIndexes = sender_indexes[sender];
        uint256 total = senderTransferIndexes.length;
        if (offset >= total) {
            return new uint256[](0);
        }
        uint256 to = offset + limit;
        if (to > total) {
            to = total;
        }
        uint256 size = to - offset;
        uint256[] memory result = new uint256[](size);
        for (uint256 i = 0; i < size; i++) {
            result[i] = senderTransferIndexes[offset + i];
        }
        return result;
    }

    
    function getTransferCount() external view returns (uint256) {
        return transfers.length;
    }
}
