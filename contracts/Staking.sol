// SPDX-License-Identifier: UNLICENSED
pragma solidity <= 0.8.10;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-solidity/contracts/access/Ownable.sol";
import "openzeppelin-solidity/contracts/utils/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "hardhat/console.sol";

contract Staking is Ownable
{
    ERC20 public stakeToken;
    uint256 public totalStakedAmount = 0;
    uint256 public totalUnStakedAmount = 0;
    
    //              min 2000    limit
    //  14 d        90          20,000,000
    //  30 d        120         20,000,000

    uint256 constant private INVALID_INDEX = 999;
    uint256 constant private twoWeekPoolLimit = 20*10**6;
    uint256 constant private oneMonthPoolLimit = 20*10**6;
    
    uint256 constant private minAmount = 2000;
    uint256 private totalStaker = 0;
    
    uint256[2] public  stakedPool = [0, 0];
    uint256[2] public  APR = [9, 12];

    struct StakerInfo {
        uint256 amount;
        uint releaseDate;
        bool isRelease;
        uint256 rewardDebt;
        uint256 termOption;        
    }

    event Stake(address indexed _from, uint _duration, uint _value);
    event UnStake(address indexed _from, uint _duration, uint _value);

    mapping(address => StakerInfo[]) public stakers;

    constructor(ERC20 _stakeToken) {
        stakeToken = _stakeToken;
    }
    function getStakedPoolIndex(uint termOption) public pure returns (uint) {
        if(termOption == 14) {
            return 0;
        }

        if(termOption == 30) {
            return 1;
        }

        return INVALID_INDEX;
    }

    function twoWeekPoolRemain() public view returns (uint) {
        return twoWeekPoolLimit * 10 ** stakeToken.decimals() - stakedPool[0];
    }

    function oneMonthkPoolRemain() public view returns (uint) {
        return oneMonthPoolLimit * 10 ** stakeToken.decimals() - stakedPool[1];
    }

    modifier underTwoWeekPoolRemain(uint _amount) {
        require(twoWeekPoolRemain() >= _amount, 'Two week pool limit reached');
        _;
    }

    modifier underOneMonthPoolRemain(uint _amount) {
        require(oneMonthkPoolRemain() >= _amount, 'One month pool limit reached');
        _;
    }

    function stake(uint _amount, uint _termOption) internal {
        // console.log('minAmount= %o, stakeToken.decimals()= %o, minAmount * 10 ** stakeToken.decimals()= %o', minAmount, stakeToken.decimals(), minAmount * 10 ** stakeToken.decimals());
        // console.log('_amount= %o, _termOption= %o', _amount, _termOption);
        require(_amount >= (minAmount * 10 ** stakeToken.decimals() ), 'Stake amount invalid');
        uint stakedPoolIndex = getStakedPoolIndex(_termOption);
        require(stakedPoolIndex != INVALID_INDEX, 'Invalid term Option');
        require(stakeToken.balanceOf(msg.sender) >= _amount, 'Insufficient balance');
        require(stakeToken.allowance(msg.sender, address(this)) >= _amount, 'Invalid amount');

        // uint256 amount;
        // uint releaseDate;
        // bool isRelease;
        // uint256 rewardDebt;
        // uint256 termOption;        

        StakerInfo memory staker = StakerInfo (
            _amount,
            block.timestamp + _termOption * 1 days,
            false,
            _termOption * _amount * APR[stakedPoolIndex] / 100 / 365,
            _termOption
        );

        stakers[msg.sender].push(staker);
        SafeERC20.safeTransferFrom(stakeToken, msg.sender, address(this), _amount);
        totalStakedAmount += _amount;
        stakedPool[stakedPoolIndex] += _amount;
        totalStaker += 1;
        emit Stake(msg.sender, _termOption, _amount);

    }

    function unStake(uint index) public {
        require(index<stakers[msg.sender].length, 'Index out of bound');
        StakerInfo storage staker = stakers[msg.sender][index];
        require(staker.releaseDate <= block.timestamp, 'You can not unstake before release date');
        uint willPaid = staker.amount + staker.rewardDebt;
        // console.log('ttt unstake bal = %o, willPaid=%o, rewardDebt=%o', stakeToken.balanceOf(address(this)), willPaid, staker.rewardDebt);
        require(willPaid <= stakeToken.balanceOf(address(this)), 'Insufficient balance');
        staker.isRelease = true;

        // console.log('before unstake bal = %o, willPaid=%o', stakeToken.balanceOf(address(this)), willPaid);
        stakeToken.transfer(msg.sender, willPaid);
        // console.log('after unstake bal = %o', stakeToken.balanceOf(address(this)));

        totalStakedAmount -= staker.amount;

        uint poolIndex = getStakedPoolIndex(staker.termOption);
        // console.log('totalStakedAmount = %o , poolIndex=%o', totalStakedAmount, poolIndex);
        // console.log('staker.amount = %o , stakedPool[poolIndex]=%o', staker.amount, stakedPool[poolIndex]);        
        stakedPool[poolIndex] -= staker.amount;
        totalStaker -= 1;
        emit UnStake(msg.sender, staker.termOption, staker.amount);
    }

    function twoWeekStake(uint _amount) underTwoWeekPoolRemain (_amount) public {
        stake(_amount, 14);
    }
    function oneMonthStake(uint _amount) underOneMonthPoolRemain (_amount) public {
        stake(_amount, 30);
    }

    function getStakerInfo(address _staker) public view returns(StakerInfo[] memory) {
        return stakers[_staker];
    }

    function getStakerInfo(address _staker, uint from, uint to) public view returns(StakerInfo[] memory) {
        StakerInfo[] memory stakerInfos = stakers[_staker];
        require(0 <= from && from < stakerInfos.length, 'Invalid from index');
        require(0 <= to && to < stakerInfos.length, 'Invalid to index');
        // uint length = to - from +1;

        StakerInfo[] memory result = new StakerInfo[] (to - from +1);
        for(uint i= from; i < to; i++) {
            result[i- from] = stakerInfos[i];
        }

        return result;
    }

    function getStakerInfoByTermOption(address _staker, uint _termOption, uint from, uint to) 
        public view returns (StakerInfo[] memory) {
        StakerInfo[] memory stakerInfos = stakers[_staker];
        require(from < to , 'From must be less than To');
        uint length = 0;

        for(uint i= from; i < stakerInfos.length; i++) {
            if( stakerInfos[i].termOption == _termOption) {
                length ++;
            }
        }

        require(0 <= from && from < length, 'Invalid from index');
        require(0 <= to && to < length, 'Invalid to index');

        uint count =0;
        uint index =0;

        StakerInfo[] memory result = new StakerInfo[] (to - from +1);
        for(uint i= from; i < stakerInfos.length; i++) {
            if( stakerInfos[i].termOption == _termOption) {
                if( from <= count && count <= to) {
                    result[index++] = stakerInfos[i];
                }
                if(count == to) {
                    break;
                }
                count ++;
            }
        }
        return result;
    }

    function getStakerInfoByRelease(address _staker, bool _isRelease, uint from, uint to) 
        public view returns (StakerInfo[] memory) {
        StakerInfo[] memory stakerInfos = stakers[_staker];
        require(from < to , 'From must be less than To');
        uint length = 0;

        for(uint i= from; i < stakerInfos.length; i++) {
            if( stakerInfos[i].isRelease == _isRelease) {
                length ++;
            }
        }

        require(0 <= from && from < length, 'Invalid from index');
        require(0 <= to && to < length, 'Invalid to index');

        uint count =0;
        uint index =0;

        StakerInfo[] memory result = new StakerInfo[] (to - from +1);
        for(uint i= from; i < stakerInfos.length; i++) {
            if( stakerInfos[i].isRelease == _isRelease) {
                if( from <= count && count <= to) {
                    result[index++] = stakerInfos[i];
                }
                if(count == to) {
                    break;
                }
                count ++;
            }
        }
        return result;
    }

    function getStakerInfoByTermOptionAndRelease(address _staker, uint _termOption, bool _isRelease, uint from, uint to) 
        public view returns (StakerInfo[] memory) {
        StakerInfo[] memory stakerInfos = stakers[_staker];
        require(from < to , 'From must be less than To');
        uint length = 0;

        for(uint i= from; i < stakerInfos.length; i++) {
            if( stakerInfos[i].isRelease == _isRelease && stakerInfos[i].termOption == _termOption) {
                length ++;
            }
        }

        require(0 <= from && from < length, 'Invalid from index');
        require(0 <= to && to < length, 'Invalid to index');

        uint count =0;
        uint index =0;

        StakerInfo[] memory result = new StakerInfo[] (to - from +1);
        for(uint i= from; i < stakerInfos.length; i++) {
            if( stakerInfos[i].isRelease == _isRelease && stakerInfos[i].termOption == _termOption) {
                if( from <= count && count <= to) {
                    result[index++] = stakerInfos[i];
                }
                if(count == to) {
                    break;
                }
                count ++;
            }
        }
        return result;
    }

    function getDetailStakedPool () public view returns (uint[2] memory) {
        return stakedPool;
    }

    function totalStakeByAddress(address _address) public view returns (uint) {
        uint total = 0;
        StakerInfo[] storage stakerInfos = stakers[_address];
        for(uint i= 0; i < stakerInfos.length; i++) {
            if(stakerInfos[i].isRelease == false) {
                total += stakerInfos[i].amount;
            }
        }

        return total;
   }

    function totalRewardDebtByAddress(address _address) public view returns (uint _staked) {
        uint total =0;
        StakerInfo[] storage stakerInfos = stakers[_address];
        for(uint i=0; i> stakerInfos.length; i++) {
            if(stakerInfos[i].isRelease == true)  {
                total += stakerInfos[i].rewardDebt;
            }
        }

        return total;
    }

    function getStakeCount(address _address) public view returns (uint) {
        uint total = 0;
        StakerInfo[] storage stakerInfos = stakers[_address];
        for(uint i= 0; i < stakerInfos.length; i++) {
            if(stakerInfos[i].isRelease == false) {
                total += 1;
            }
        }

        return total;
    }

    function getStakeInfo(address _staker, uint _index) 
        public view returns (uint _amount, uint _releaseDate, bool _isRelease, uint _reward) {
        StakerInfo memory staker = stakers[_staker][_index];

        return (staker.amount, staker.releaseDate, staker.isRelease, staker.rewardDebt);
    }

    function totalStakerInfoByTermOption(address _staker, uint _termOption) 
        public view returns (uint) {
        uint total =0;
        StakerInfo[] storage stakerInfos = stakers[_staker];
        for(uint i= 0; i < stakerInfos.length; i++) {
            if(stakerInfos[i].termOption == _termOption) {
                total ++;
            }
        }
       
       return total;
    }

    function totalStakerInfoByTermOptionAndRelease(address _staker, uint _termOption, bool _isRelease) 
        public view returns (uint) {
        uint total =0;
        StakerInfo[] storage stakerInfos = stakers[_staker];
        for(uint i= 0; i < stakerInfos.length; i++) {
            if(stakerInfos[i].termOption == _termOption && stakerInfos[i].isRelease == _isRelease) {
                total ++;
            }
        }
       
       return total;
    }    
    function totalStakerInfoByRelease(address _staker, bool _isRelease) 
        public view returns (uint) {
        uint total =0;
        StakerInfo[] storage stakerInfos = stakers[_staker];
        for(uint i= 0; i < stakerInfos.length; i++) {
            if(stakerInfos[i].isRelease == _isRelease) {
                total ++;
            }
        }
       
       return total;
    }        
}