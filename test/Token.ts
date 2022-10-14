import { BigNumber } from '@ethersproject/bignumber'
import { Contract } from '@ethersproject/contracts'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { formatEther } from '@ethersproject/units'
import * as chai from 'chai'
import { expect } from 'chai'
const chaiAsPromised = require('chai-as-promised')
import { ethers } from 'hardhat'
import { keccak256 } from 'ethers/lib/utils'

chai.use(chaiAsPromised)

async function  deployStaking(deployer: SignerWithAddress, amount: number) {
  const Token = await ethers.getContractFactory('Floppy', deployer);
  const token = await Token.deploy();

  const Bank = await ethers.getContractFactory('Staking', deployer);
  const bank = await Bank.deploy(token.address);

  await token.transfer(bank.address, BigNumber.from(amount).mul(parseEther(1)));

  return [token, bank];
}

function parseEther(amount: Number) {
  return ethers.utils.parseUnits(amount.toString(), 18)
}
describe('Staking Contract', async () => {
  it('Should deploy',async()=>{
    const [owner] = await ethers.getSigners();
    await deployStaking(owner, 20);
  });

  it('Should validate stake amount', async()=>{
    const [owner, staker] = await ethers.getSigners();
    const [token, bank] = await deployStaking(owner, 20);

    await token.transfer(staker.address, parseEther(100*10**6));
    await token.connect(staker).approve(bank.address, token.balanceOf(staker.address));

    await expect(bank.connect(staker).twoWeekStake(parseEther(300)))
      .to.be.revertedWith('Stake amount invalid');
  });

  it('Should reach pool limit', async()=>{
    const [owner, staker] = await ethers.getSigners();
    const [token, bank] = await deployStaking(owner, 20);

    await token.transfer(staker.address, parseEther(100*10**6));
    await token.connect(staker).approve(bank.address, token.balanceOf(staker.address));

    await expect(bank.connect(staker).twoWeekStake(parseEther(21*10**6)))
      .to.be.revertedWith('Two week pool limit reached');
      await expect(bank.connect(staker).oneMonthStake(parseEther(21*10**6)))
      .to.be.revertedWith('One month pool limit reached');
  });

  it('Should exceed balance', async()=>{
    const [owner, staker] = await ethers.getSigners();
    const [token, bank] = await deployStaking(owner, 20);

    await token.transfer(staker.address, parseEther(1*10**6));
    await token.connect(staker).approve(bank.address, token.balanceOf(staker.address));

    await expect(bank.connect(staker).twoWeekStake(parseEther(2*10**6)))
      .to.be.revertedWith('Insufficient balance');
    await expect(bank.connect(staker).oneMonthStake(parseEther(2*10**6)))
      .to.be.revertedWith('Insufficient balance');
  });

  it('Should stake 2 week', async()=>{
    const [owner, staker] = await ethers.getSigners();
    const [token, bank] = await deployStaking(owner, 20);
    const bankBalanceBefore = await token.balanceOf(bank.address);

    await token.transfer(staker.address, parseEther(1*10**6));
    await token.connect(staker).approve(bank.address, token.balanceOf(staker.address));

    await bank.connect(staker).twoWeekStake(parseEther(500*10**3));
    await bank.connect(staker).twoWeekStake(parseEther(500*10**3));

    // stake 2 times
    expect(await bank.getStakeCount(staker.address)).to.equal(BigNumber.from(2));
    expect(await bank.totalStakeByAddress(staker.address)).to.equal(parseEther(1*10**6));

    const bankBlanceAfter = await token.balanceOf(bank.address);
    // console.log(bankBalanceBefore, bankBlanceAfter, parseEther(1*10**6));
    expect(bankBlanceAfter.sub(bankBalanceBefore)).to.equal(parseEther(1*10**6));
  });

  it('Should stake 1 month', async()=>{
    const [owner, staker] = await ethers.getSigners();
    const [token, bank] = await deployStaking(owner, 100);
    const bankBalanceBefore = await token.balanceOf(bank.address);

    await token.transfer(staker.address, parseEther(1*10**6));
    await token.connect(staker).approve(bank.address, token.balanceOf(staker.address));

    await bank.connect(staker).oneMonthStake(parseEther(500*10**3));
    await bank.connect(staker).oneMonthStake(parseEther(500*10**3));

    // stake 2 times
    expect(await bank.getStakeCount(staker.address)).to.equal(BigNumber.from(2));
    expect(await bank.totalStakeByAddress(staker.address)).to.equal(parseEther(1*10**6));

    const bankBlanceAfter = await token.balanceOf(bank.address);
    expect(bankBlanceAfter.sub(bankBalanceBefore)).to.equal(parseEther(1*10**6));
  });

  it('Should unstake fail before release date', async()=>{
    const [owner, staker] = await ethers.getSigners();
    const [token, bank] = await deployStaking(owner, 50000);
    const bankBalanceBefore = await token.balanceOf(bank.address);

    await token.transfer(staker.address, parseEther(1*10**6));
    await token.connect(staker).approve(bank.address, token.balanceOf(staker.address));

    await bank.connect(staker).twoWeekStake(parseEther(500*10**1));
    await bank.connect(staker).oneMonthStake(parseEther(500*10**1));

    const bankBlanceAfter = await token.balanceOf(bank.address);
    expect(await bankBlanceAfter.sub(bankBalanceBefore)).to.equal(parseEther(1*10**4));

    await expect(bank.connect(staker).unStake(BigNumber.from(10)))
      .to.be.revertedWith('Index out of bound');

    //  unstake 2 week stake
    await expect(bank.connect(staker).unStake(BigNumber.from(0)))
      .to.be.revertedWith('You can not unstake before release date');

    // time travel to 15 days later
    await ethers.provider.send('evm_increaseTime', [15*24*60*60]);
    await ethers.provider.send('evm_mine', []);

    //  unstake 2 week success
    await bank.connect(staker).unStake(BigNumber.from(0));

    //  unstake 1 month false: TODO check this!!!
    await expect(bank.connect(staker).unStake(BigNumber.from(1)))
      .to.be.revertedWith('You can not unstake before release date');
  });  
})
