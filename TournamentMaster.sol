

pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2;

contract Tournament {
    // STRUCTS AND ENUMS
    // Stores data about each contestant
    struct Contestant {
        address addr;
        uint256 matchID;  // Current Match it is in; this ensures that each contestant is only present in any one match at the same time
        mapping(string => uint256) attributes;  // Straighforward attribute record with name and numerical value
        // uint256 balance;
    }

    // Comparison options when criteria used to filter out winners for a match
    enum Compare { LT, LTE, GT, GTE, EQ }

    // Indicator for the current temporal status of a match
    enum MatchStatus { UPCOMING, CURRENT, COMPLETED }

    // Represents a match and its participating contestants
    struct Match {
        address[] contestantsQueue;  // Stores addresses of all participating contestants for this match
        mapping(address => address) contestants;  // Self-map confirms participation of specific contestants; mapping acts as an unordered set
        mapping(address => uint256) contestantScores;  // Continously updated to reflect real-time scores during and after a match for each contestant
        MatchStatus status;
        address winner;
        uint256 matchID;  // Must be unique and equal to the match counter, meaning the ID of n^th created match is n
    }

    // Holds (x, y) coordinate pair to locate a certain Match struct object in tournamentTree
    struct PairIndex {
        uint256 round;
        uint256 pos;
    }

    // VARIABLES
    uint256 private numContestants;  // Number of contestants overall
    uint256 private numRounds;  // Number of rounds so far
    uint256 private numInitialMatches;  // Number of initial matches i.e. the number of leaves in tournament tree
    uint256 private K;  // the number of winners in the end
    PairIndex[] private matchLocator;  // Stores PairIndex for each existing Match object based on its matchID as array index
    mapping(address => Contestant) private contestants;  // Record of all participating contestants throughout entire tournament
    mapping(uint256 => Match[]) private tournamentTree;  // Contains all the matches, regardless of status, organized by round (level) and position within each round

    // METHODS
    constructor(uint256 _numInitialMatches, uint256 _K) public {
        require(_numInitialMatches >= 2, "The number of initial matches must be at least 2 to begin with.");
        require(_numInitialMatches & (_numInitialMatches - 1) == 0, "The number of initial matches must be a power of 2.");
        numContestants = 0;
        numRounds = 0;
        matchLocator.push(PairIndex({round: 0, pos: 0}));  // Default to fill 0-index so index equals position for real PairIndex objects
        numInitialMatches = _numInitialMatches;
        K = _K;
    }

    // CONTESTANT MATHODS
    function addContestant(address _addr) public returns (uint256 _numContestants) {
        require(contestants[_addr].addr != address(0), "Contestant must not already exist.");
        contestants[_addr] = Contestant({addr: _addr, matchID: 0});
        return ++numContestants;
    }

    function setAttribute(address _addr, string memory _attrName, uint256 _attrValue) public {
        require(contestants[_addr].addr != address(0), "Contestant must not already exist.");
        contestants[_addr].attributes[_attrName] = _attrValue;
    }

    function setAttributeBatch(address _addr, string[] memory _attrNameArr, uint256[] memory _attrValueArr) public {
        require(_attrNameArr.length == _attrValueArr.length, "Attribute names array and attribute values array must have same length.");
        for(uint256 i = 0; i < _attrNameArr.length; i++) {
            setAttribute(_addr, _attrNameArr[i], _attrValueArr[i]);
        }
    }

    // MATCH METHODS
    function checkMatchStatus(uint256 _matchID) public view returns (MatchStatus) {
        require(_matchID < matchLocator.length && _matchID >= 1, "_matchID is out of bounds; it must be between 1 and number of existing Match objects inclusively.");
        PairIndex memory pi = matchLocator[_matchID];
        return tournamentTree[pi.round][pi.pos].status;
    }

    function setMatchStatus(uint256 _matchID, MatchStatus ms) private {
        require(_matchID < matchLocator.length && _matchID >= 1, "_matchID is out of bounds; it must be between 1 and number of existing Match objects inclusively.");
        PairIndex memory pi = matchLocator[_matchID];
        tournamentTree[pi.round][pi.pos].status = ms;
    }

    function registerContestant(uint256 _matchID, address _addr) private {
        require(_matchID < matchLocator.length && _matchID >= 1, "_matchID is out of bounds; it must be between 1 and number of existing Match objects inclusively.");
        require(_matchID != contestants[_addr].matchID, "Contestant is already registered in this match.");
        contestants[_addr].matchID = _matchID;  // Changing matchID on state variable for contestants
        PairIndex memory pi = matchLocator[_matchID];

        // Registering contestant into specified Match object
        tournamentTree[pi.round][pi.pos].contestantsQueue.push(_addr);
        tournamentTree[pi.round][pi.pos].contestants[_addr] = _addr;
    }

    /*
    * Helper function to do the actual work of instantiating a new Natch object and inserting that into the rounament tree
    * @param _matchID [uint256] - New matchID to be used for new Match object
    * @param capacity [uint256] - Maximum number of contestants allowed in this match; unused slots will be address(0)
    * @returns numMatches [@unint256] - The total number of matches after creating this one
    */
    function createMatch(uint256 _matchID, uint256 capacity) private view returns (Match memory mch) {
        require(_matchID == matchLocator.length, "New matchID must be the integer right after current count of Match objects.");
        require(capacity >= 2, "Capacity must be at least 2.");
        return Match({contestantsQueue: new address[](capacity), status: MatchStatus.UPCOMING, winner: address(0), matchID: _matchID});
    }

    function createMatchFromWinners(uint256 round, uint256 pos) private returns (uint256 numMatches) {
        require(round > numRounds, "Specified round has not even occurred yet.");
        require(pos + 1 > getMatchCountInRound(round), "Invalid position for second adjacent match." );
        uint256 nextRound = round + 1;

        // Enlarging state variables to accomodate new Match object
        uint256 newMatchID = matchLocator.length;
        if(nextRound > numRounds) {
            tournamentTree[nextRound] = new Match[](getMatchCountInRound(nextRound) + 1);
            tournamentTree[nextRound].push(Match({contestantsQueue: new address[](0), status: MatchStatus.UPCOMING, winner: address(0), matchID: 0}));  // Default Match object
        }
        tournamentTree[nextRound].push(createMatch(matchLocator.length, 2));
        matchLocator.push(PairIndex({round: nextRound, pos: getMatchCountInRound(nextRound)}));

        // Entering winners from matches with positions between pos and pos + 1 inclusive
        address winnerAddr = tournamentTree[round][pos].winner;
        registerContestant(newMatchID, winnerAddr);
        winnerAddr = tournamentTree[round][pos + 1].winner;
        registerContestant(newMatchID, winnerAddr);
        return newMatchID;
    }

    // TOURNAMENT TREE METHODS
    function getNumberOfRounds() public view returns (uint256) {
        return numRounds - 1;
    }

    function getMatchCountInRound(uint256 round) public view returns (uint256) {
        require(round > numRounds, "Specified round has not even occurred yet."); 
        return numInitialMatches / 2**round;
    }

    function firstRound() private view returns (Match[] memory arr) {
        return tournamentTree[1];
    }

    function lastRound() private view returns (Match[] memory arr) {
        return tournamentTree[getNumberOfRounds()];
    }

    function init() public {
        uint256 contestantsPerInitMatch = numContestants / numInitialMatches;  // Number of contestants per initial match (leaf node) except for possibly the last one
        for(uint256 i = 1; i <= numInitialMatches; i++) {
            createMatch(1, contestantsPerInitMatch);
            for(uint256 j = 1; j <= contestantsPerInitMatch; j++) {
                registerContestant(i, address(i * j));
            }
        }
    }

    function executeMatch(address _matchID) public {
        /* Enter function for specific criteria in choosing a winner from contestants in Match object */
        // PairIndex memory pi = matchLocator[_matchID];
        // tournamentTree[pi.round][pi.pos].status = MatchStatus.COMPLETED;
        // tournamentTree[pi.round][pi.pos].winner = tournamentTree[pi.round][pi.pos].contestantsQueue[0];
    }

    function execute() public {
        uint256 numMatches = numInitialMatches;  // Number of matches in this round
        numRounds = 1;
        while(numMatches >= 1) {
            for(uint256 i = 1; i <= numMatches; i++) {
                executeMatch(address(0));
                numRounds++;
            }
        }
    }
   
}

