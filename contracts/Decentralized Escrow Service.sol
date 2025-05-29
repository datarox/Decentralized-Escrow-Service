// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract EscrowService {
    // State variables
    uint256 public escrowCounter;
    address public owner;
    uint256 public serviceFeePercent = 1; // 1% service fee
    
    enum EscrowStatus { 
        PENDING, 
        FUNDED, 
        COMPLETED, 
        DISPUTED, 
        REFUNDED, 
        CANCELLED 
    }
    
    struct Escrow {
        uint256 id;
        address buyer;
        address seller;
        uint256 amount;
        string description;
        EscrowStatus status;
        uint256 createdAt;
        uint256 deadline;
        bool buyerApproval;
        bool sellerApproval;
    }
    
    mapping(uint256 => Escrow) public escrows;
    mapping(address => uint256[]) public userEscrows;
    
    // Events
    event EscrowCreated(
        uint256 indexed escrowId, 
        address indexed buyer, 
        address indexed seller, 
        uint256 amount
    );
    event EscrowFunded(uint256 indexed escrowId, uint256 amount);
    event EscrowCompleted(uint256 indexed escrowId);
    event EscrowRefunded(uint256 indexed escrowId);
    event EscrowDisputed(uint256 indexed escrowId);
    event ApprovalGiven(uint256 indexed escrowId, address indexed approver);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier onlyParties(uint256 _escrowId) {
        require(
            msg.sender == escrows[_escrowId].buyer || 
            msg.sender == escrows[_escrowId].seller,
            "Only buyer or seller can call this function"
        );
        _;
    }
    
    modifier escrowExists(uint256 _escrowId) {
        require(_escrowId > 0 && _escrowId <= escrowCounter, "Escrow does not exist");
        _;
    }
    
    modifier onlyBuyer(uint256 _escrowId) {
        require(msg.sender == escrows[_escrowId].buyer, "Only buyer can call this function");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        escrowCounter = 0;
    }
    
    // Core Function 1: Create Escrow
    function createEscrow(
        address _seller,
        string memory _description,
        uint256 _deadline
    ) public payable {
        require(msg.value > 0, "Escrow amount must be greater than 0");
        require(_seller != msg.sender, "Seller cannot be the same as buyer");
        require(_seller != address(0), "Invalid seller address");
        require(_deadline > block.timestamp, "Deadline must be in the future");
        
        escrowCounter++;
        
        Escrow storage newEscrow = escrows[escrowCounter];
        newEscrow.id = escrowCounter;
        newEscrow.buyer = msg.sender;
        newEscrow.seller = _seller;
        newEscrow.amount = msg.value;
        newEscrow.description = _description;
        newEscrow.status = EscrowStatus.FUNDED;
        newEscrow.createdAt = block.timestamp;
        newEscrow.deadline = _deadline;
        newEscrow.buyerApproval = false;
        newEscrow.sellerApproval = false;
        
        userEscrows[msg.sender].push(escrowCounter);
        userEscrows[_seller].push(escrowCounter);
        
        emit EscrowCreated(escrowCounter, msg.sender, _seller, msg.value);
        emit EscrowFunded(escrowCounter, msg.value);
    }
    
    // Core Function 2: Release Funds
    function releaseFunds(uint256 _escrowId) 
        public 
        escrowExists(_escrowId) 
        onlyParties(_escrowId) 
    {
        Escrow storage escrow = escrows[_escrowId];
        require(escrow.status == EscrowStatus.FUNDED, "Escrow is not in funded state");
        require(block.timestamp <= escrow.deadline, "Escrow has expired");
        
        if (msg.sender == escrow.buyer) {
            escrow.buyerApproval = true;
        } else if (msg.sender == escrow.seller) {
            escrow.sellerApproval = true;
        }
        
        emit ApprovalGiven(_escrowId, msg.sender);
        
        // If both parties approve, release funds to seller
        if (escrow.buyerApproval && escrow.sellerApproval) {
            escrow.status = EscrowStatus.COMPLETED;
            
            uint256 serviceFee = (escrow.amount * serviceFeePercent) / 100;
            uint256 sellerAmount = escrow.amount - serviceFee;
            
            // Transfer funds to seller
            payable(escrow.seller).transfer(sellerAmount);
            
            // Transfer service fee to owner
            if (serviceFee > 0) {
                payable(owner).transfer(serviceFee);
            }
            
            emit EscrowCompleted(_escrowId);
        }
    }
    
    // Core Function 3: Refund Escrow
    function refundEscrow(uint256 _escrowId) 
        public 
        escrowExists(_escrowId) 
    {
        Escrow storage escrow = escrows[_escrowId];
        require(escrow.status == EscrowStatus.FUNDED, "Escrow is not in funded state");
        
        bool canRefund = false;
        
        // Buyer can refund if deadline has passed and seller hasn't approved
        if (msg.sender == escrow.buyer && block.timestamp > escrow.deadline && !escrow.sellerApproval) {
            canRefund = true;
        }
        
        // Owner can refund in case of disputes
        if (msg.sender == owner) {
            canRefund = true;
        }
        
        // Both parties can agree to refund
        if (msg.sender == escrow.buyer || msg.sender == escrow.seller) {
            if (escrow.buyerApproval && escrow.sellerApproval) {
                canRefund = true;
            }
        }
        
        require(canRefund, "Refund conditions not met");
        
        escrow.status = EscrowStatus.REFUNDED;
        payable(escrow.buyer).transfer(escrow.amount);
        
        emit EscrowRefunded(_escrowId);
    }
    
    // Additional utility functions
    function disputeEscrow(uint256 _escrowId) 
        public 
        escrowExists(_escrowId) 
        onlyParties(_escrowId) 
    {
        Escrow storage escrow = escrows[_escrowId];
        require(escrow.status == EscrowStatus.FUNDED, "Escrow is not in funded state");
        
        escrow.status = EscrowStatus.DISPUTED;
        emit EscrowDisputed(_escrowId);
    }
    
    function getEscrowDetails(uint256 _escrowId) 
        public 
        view 
        escrowExists(_escrowId) 
        returns (
            address buyer,
            address seller,
            uint256 amount,
            string memory description,
            EscrowStatus status,
            uint256 deadline,
            bool buyerApproval,
            bool sellerApproval
        ) 
    {
        Escrow storage escrow = escrows[_escrowId];
        return (
            escrow.buyer,
            escrow.seller,
            escrow.amount,
            escrow.description,
            escrow.status,
            escrow.deadline,
            escrow.buyerApproval,
            escrow.sellerApproval
        );
    }
    
    function getUserEscrows(address _user) public view returns (uint256[] memory) {
        return userEscrows[_user];
    }
    
    function updateServiceFee(uint256 _newFeePercent) public onlyOwner {
        require(_newFeePercent <= 5, "Service fee cannot exceed 5%");
        serviceFeePercent = _newFeePercent;
    }
    
    function emergencyWithdraw(uint256 _escrowId) public onlyOwner escrowExists(_escrowId) {
        Escrow storage escrow = escrows[_escrowId];
        require(escrow.status == EscrowStatus.DISPUTED, "Escrow must be in disputed state");
        
        // Owner can manually resolve disputes
        escrow.status = EscrowStatus.REFUNDED;
        payable(escrow.buyer).transfer(escrow.amount);
        
        emit EscrowRefunded(_escrowId);
    }
}
