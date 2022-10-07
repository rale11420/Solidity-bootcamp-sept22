// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/ReentrancyGuard.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Strings.sol";

error FlightAlreadyDeparted();

/// @title MVPWAirlines
/// @author Rastko Misulic
/// @notice You can use this contract for scheduling/canceling flights, register airplanes, buying/canceling tickets...
/// @dev Functions use ERC20 - MVPWAIR token, 
/// @dev Ownable for ownership managament and ReentrancyGuard for protecting from agressive fund withdraw
contract MVPWAirlines is Ownable, ReentrancyGuard {
    
    //using Strings for uint256;

    struct Airplane {
        uint256 numOfSeatsFirst;
        uint256 numOfSeatsEconomy;
        bool onHold;
        string previousFlights;        
    }

    struct Flight {
        Airplane airplane;
        string destination;
        uint256 departedTime;
        uint256 priceFirst;
        uint256 priceEco;
    }

    struct Ticket {
        address buyer;
        uint256 amountPaid;
        uint256 flightID;
        SeatClasses seatClass;
    }

    enum SeatClasses {
        first, economy
    }

    uint256 numOfAirplanes;
    uint256 numOfFlights;
    uint256 numOfTickets;
    uint256 timeOfLatestFlight;
    mapping(address => bool) private ownershipApprovals;
    mapping(uint256 => Airplane) public airplanes;
    mapping(uint256 => Flight) public flights;
    mapping(uint256 => mapping(address => uint256)) public numberOfTicketsBought;
    mapping(uint256 => Ticket) public tickets;
    IERC20 public immutable token;

    //events
    event AdminChanged(address indexed newAdmin);
    event AirplaneOnHold(uint256 airplaneID);
    event AirplaneAvailable(uint256 airplaneID);
    event AirplaneRegistered(uint256 airplaneID);
    event AirplaneDeleted(uint airplaneID);
    event FlightScheduled(uint256 flightID);
    event FlightCanceled(uint256 flightID);
    event TicketBought(uint256 flightID, address buyer, SeatClasses seatClass);
    event TicketCanceled(uint256 ticketID, address exBuyer);

    //modifiers
    modifier ValidAirplaneID(uint _airplaneID) {
        require(_airplaneID <= numOfAirplanes, "Invalid airplane ID");
        _;
    }

    /// @notice token address: 0x71bDd3e52B3E4C154cF14f380719152fd00362E7 (Goerli)
    constructor(IERC20 _tokenAddress) {
        token = IERC20(_tokenAddress);
        timeOfLatestFlight = block.timestamp;
    }

    /// @notice Sets approval from potential new admin
    /// @dev Updates mapping with approvals
    function acceptNewAdminRole() external {
        require(msg.sender != owner(), "Already owner");
        ownershipApprovals[msg.sender] = true;
    }

    /// @notice Cancel approval from potential new admin
    /// @dev Updates mapping with approvals    
    function cancelNewAdminRole() external {
        require(msg.sender != owner(), "Already owner");
        ownershipApprovals[msg.sender] = false;
    }

    /// @notice Sets new admin if terms are met
    /// @dev Changes admin, updates mapping with approvals
    /// @dev Emits AdminChanged event with new admin address
    /// @param _newAdmin - new Admin address
    function changeAdmin(address _newAdmin) external onlyOwner {
        require(msg.sender != _newAdmin, "Already owner");
        require(_newAdmin != address(0x0), "Admin == 0x0");
        transferOwnership(_newAdmin);
        ownershipApprovals[_newAdmin] = false;

        emit AdminChanged(_newAdmin);
    }

    /// @notice Puts airplane on hold due to malfunction
    /// @dev Updates airplane status
    /// @dev Emits AirplaneOnHold event with airplane ID
    /// @param airplaneID - airplane ID from mapping
    function putAirplaneOnHold(uint256 airplaneID) external onlyOwner ValidAirplaneID(airplaneID) {
        airplanes[airplaneID].onHold = true;

        emit AirplaneOnHold(airplaneID);
    }

    /// @notice Sets airplane back in action
    /// @dev Updates airplane status
    /// @dev Emits AirplaneAvailable event with airplane ID
    /// @param airplaneID - airplane ID from mapping
    function putAirplaneAvailable(uint256 airplaneID) external onlyOwner ValidAirplaneID(airplaneID) {
        airplanes[airplaneID].onHold = false;

        emit AirplaneAvailable(airplaneID);
    }

    /// @notice Register new airplane
    /// @dev Updates mapping with valuable info
    /// @dev Uses numOfAirplanes as index in mapping
    /// @dev Emits AirplaneRegistered event with last index in airplanes mapping
    /// @param numFirst - number of seats in first class
    /// @param numFirst - number of seats in economy class
    function registerAirplane(uint256 numFirst, uint256 numEco) external onlyOwner {
        airplanes[numOfAirplanes] = Airplane(numFirst, numEco, false, "");

        emit AirplaneRegistered(numOfAirplanes);

        numOfAirplanes++;
    }    

    /// @notice Delete airplane from mapping
    /// @dev Emits AirplaneDeleted event with last index in airplanes mapping    
    /// @param airplaneID - airplane ID from mapping
    function deleteAirplane(uint256 airplaneID) external onlyOwner ValidAirplaneID(airplaneID){
        delete(airplanes[airplaneID]);

        emit AirplaneDeleted(airplaneID);
    }

    /// @notice Sets new flight with aditional info
    /// @dev Updates mapping with valuable info
    /// @dev Uses numOfFlights as index in mapping
    /// @dev Emits FlightScheduled event with last index in flights mapping
    /// @param _airplaneID - airplane ID from mapping
    /// @param _destination - final destination
    /// @param _departedTime - time when airplane take off
    /// @param _priceFirst - price of seats in first class
    /// @param _priceEco - price of seats in economy class
    function scheduleFlight(uint256 _airplaneID, string calldata _destination, uint256 _departedTime, uint256 _priceFirst, uint256 _priceEco) external onlyOwner ValidAirplaneID(_airplaneID) {
        require(_departedTime > block.timestamp, "Invalid departed time");

        timeOfLatestFlight = _departedTime > timeOfLatestFlight ? _departedTime : timeOfLatestFlight;
        Airplane memory temp = airplanes[_airplaneID];
        require(!temp.onHold, "Airplane on hold");
        airplanes[_airplaneID].previousFlights = string.concat(temp.previousFlights, "[", Strings.toString(numOfFlights), " ", _destination, " ", Strings.toString(_departedTime),"]");
        flights[numOfFlights] = Flight(temp, _destination, _departedTime, _priceFirst, _priceEco);

        emit FlightScheduled(numOfFlights);

        numOfFlights++;
    }

    /// @notice Cancel flight before it starts
    /// @dev Delete flight from mapping
    /// @dev Emits FlightCanceled event with index in flights mapping
    /// @param _flightID - flight ID in mapping
    function cancelFlight(uint256 _flightID) external onlyOwner {
        require(_flightID <= numOfFlights, "Invalid flight ID");
        if(block.timestamp < flights[_flightID].departedTime) {
            revert FlightAlreadyDeparted();
        }

        delete(flights[_flightID]);

        emit FlightCanceled(_flightID);
    }

    /// @notice Function for buying tickets
    /// @dev Uses nonReentrant modifier to be saved from Reentrancy attack
    /// @dev Emits TicketBought event with index in flights mapping and buyer address
    /// @param _flightID - flight ID in mapping
    /// @param _seatClass - seat class(first, economy)
    /// @param price - amount of ERC20 sent by user
    function buyTicket(uint256 _flightID, SeatClasses _seatClass, uint256 price) external nonReentrant {
        require(_flightID <= numOfFlights, "Invalid flight ID");
        Flight memory temp = flights[_flightID];
        require(!temp.airplane.onHold, "Airplane on hold");
        require(numberOfTicketsBought[_flightID][msg.sender] < 4, "Already bought max amount of tickets");
        uint256 totalSeatsAvailable = temp.airplane.numOfSeatsFirst + temp.airplane.numOfSeatsEconomy;
        uint256 amount;
        require(totalSeatsAvailable > 0, "No available seats");
        if(_seatClass == SeatClasses.first) {
            require(temp.airplane.numOfSeatsFirst > 0 && temp.priceFirst <= price);
            flights[_flightID].airplane.numOfSeatsFirst--;
            amount = temp.priceFirst;
        }
        else {
            require(temp.airplane.numOfSeatsEconomy > 0 && temp.priceEco <= price);
            flights[_flightID].airplane.numOfSeatsEconomy--;
            amount = temp.priceEco;
        }

        numberOfTicketsBought[_flightID][msg.sender]++;
        tickets[numOfTickets] = Ticket(msg.sender, amount, _flightID, _seatClass);
        numOfTickets++;
        //popravi
        (bool success) = IERC20(token).transferFrom(msg.sender, address(this), amount);
        require(success); 

        emit TicketBought(_flightID, msg.sender, _seatClass);
    }  

    /// @notice Function for canceling tickets
    /// @dev Delete ticket from mapping
    /// @dev Using calculateAmountToPayBack function for calculating amount to payback
    /// @dev Using nonReentrant modifier to be saved from Reentrancy attack
    /// @dev Emits TicketCanceled event with index in tickets mapping and user address
    /// @param _ticketID - ticket ID in mapping
    function cancelTicket(uint256 _ticketID) external nonReentrant {
        require(_ticketID <= numOfTickets, "Invalid ticket ID");
        Ticket memory temp = tickets[_ticketID];
        if(block.timestamp < flights[temp.flightID].departedTime) {
            revert FlightAlreadyDeparted();
        }

        if(temp.seatClass == SeatClasses.first) {
            flights[temp.flightID].airplane.numOfSeatsFirst++;
        }
        else {
            flights[temp.flightID].airplane.numOfSeatsEconomy++;
        }

        uint256 amount = calculateAmountToPayBack(temp.flightID);
        numberOfTicketsBought[temp.flightID][msg.sender]--;
        delete(tickets[_ticketID]);

        IERC20(token).approve(address(this), amount);
        (bool success) = IERC20(token).transfer(msg.sender, amount);
        require(success);     
          
        emit TicketCanceled(_ticketID, msg.sender);
    }

    /// @notice Enables admin to withdraw funds
    /// @dev Transfers token from contract to admin
    /// @dev Check if all airplanes are departed
    /// @dev Using nonReentrant modifier to be saved from Reentrancy attack
    function withdraw() external onlyOwner {
        require(block.timestamp > timeOfLatestFlight, "There are airplanes to take off");
        uint amount = token.balanceOf(address(this));

        IERC20(token).approve(address(this), amount);
        (bool success) = IERC20(token).transfer(msg.sender, amount);
        require(success);        
    }

    // Calculates amount to payback
    function calculateAmountToPayBack(uint256 _ticketID) internal view returns(uint256 amountToPayBack) {
        require(_ticketID <= numOfTickets, "Invalid ticket ID");
        Ticket memory temp = tickets[_ticketID];
        uint256 timeDiference =  flights[temp.flightID].departedTime - block.timestamp;
        uint256 _price = temp.amountPaid;
        amountToPayBack = timeDiference > 48*60*60 ? _price : (timeDiference > 24*60*60 ? ((_price * 80)/100) : 0);
    }
}
