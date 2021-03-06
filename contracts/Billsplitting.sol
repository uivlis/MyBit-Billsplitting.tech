pragma solidity ^0.4.24;

/// @title Billsplitting contract
/// @author Peter Phillips, MyBit Foundation
/// @notice Allows users to contribute money towards a bill and send it to another wallet

import './SafeMath.sol';
import './Database.sol';
import './MyBitBurner.sol';

contract Billsplitting {
  using SafeMath for uint;

  Database public database;
  MyBitBurner public mybBurner;
  address public owner;

  uint private decimals = 10**18;
  uint public mybFee = uint(250).mul(decimals);
  bool public expired = false;

  constructor(address _database, address _mybTokenBurner) public{
    owner = msg.sender;
    database = Database(_database);
    mybBurner = MyBitBurner(_mybTokenBurner);
  }

  function createBillEqual(address _receiver, uint _total, address[] _payers)
  external {
    require(_payers.length <= 50);
    require(mybBurner.burn(msg.sender, mybFee));
    uint owingSum = 0;
    uint payerOwing = _total.div(_payers.length);
    //Need to figure out a way to make billID more unique, maybe pass an Invoice #?
    bytes32 id = keccak256(abi.encodePacked(_receiver, _total));

    database.setUint(keccak256(abi.encodePacked('billsplittingBill', id)), _total);
    database.setUint(keccak256(abi.encodePacked('billsplittingCollected', id)), 0);
    database.setAddress(keccak256(abi.encodePacked('billsplittingReceiver', id)), _receiver);
    database.setUint(keccak256(abi.encodePacked('billsplittingTotalPayers', id)), _payers.length);

    //To account for rounding issues, last payer just takes the remainder of total owing.
    for(uint i=0; i<_payers.length-1; i++){
      database.setAddress(keccak256(abi.encodePacked('billsplittingPayer', id, i)), _payers[i]);
      database.setUint(keccak256(abi.encodePacked('billsplittingOwing', id, _payers[i])), payerOwing);
      owingSum = owingSum.add(payerOwing);
    }
    database.setAddress(keccak256(abi.encodePacked('billsplittingPayer', id, _payers.length-1)), _payers[_payers.length-1]);
    database.setUint(keccak256(abi.encodePacked('billsplittingOwing', id, _payers[_payers.length-1])), _total.sub(owingSum));

    emit LogNewBill(id, _receiver, _total);
  }

  function getTotalOwing(bytes32 _billID)
  view
  external
  returns(uint owe){
    owe = database.uintStorage(keccak256(abi.encodePacked('billsplittingBill', _billID))).sub( database.uintStorage(keccak256(abi.encodePacked('billsplittingCollected', _billID))) );
    return owe;
  }

  function getUserOwing(bytes32 _billID)
  view
  external
  returns(uint owe){
    owe = database.uintStorage(keccak256(abi.encodePacked('billsplittingOwing', _billID, msg.sender)));
    return owe;
  }

  function payShare(bytes32 _billID)
  payable
  external{
    require(database.uintStorage(keccak256(abi.encodePacked('billsplittingOwing', _billID, msg.sender))) > 0);
    require(msg.value > 0);
    uint paid;
    uint owe = database.uintStorage(keccak256(abi.encodePacked('billsplittingOwing', _billID, msg.sender)));
    //In case of overpay, is it needed?
    if(msg.value > owe){
      uint refund = msg.value.sub(owe);
      msg.sender.transfer(refund);
      paid = owe;
    } else {
      paid = msg.value;
    }
    database.setUint(keccak256(abi.encodePacked('billsplittingOwing', _billID, msg.sender)), owe.sub(paid));
    database.setUint(keccak256(abi.encodePacked('billsplittingCollected', _billID)), database.uintStorage(keccak256(abi.encodePacked('billsplittingCollected', _billID))).add(paid) );
  }

  function releaseFunds(bytes32 _billID)
  external{
    require( database.uintStorage(keccak256(abi.encodePacked('billsplittingCollected', _billID))) >= database.uintStorage(keccak256(abi.encodePacked('billsplittingBill', _billID))) );
    database.addressStorage(keccak256(abi.encodePacked('billsplittingReceiver', _billID))).transfer( database.uintStorage(keccak256(abi.encodePacked('billsplittingBill', _billID))) );
  }

  //function createBill() external{}
  function changeUserAddress(bytes32 _billID, address _newAddress)
  external{
    require(_newAddress != address(0));
    uint totalPayers = database.uintStorage(keccak256(abi.encodePacked('billsplittingTotalPayers', _billID)));
    for(uint i=0; i<totalPayers; i++){
      //emit LogAddress(database.addressStorage(keccak256(abi.encodePacked('billsplittingPayer', _billID, i))));
      if(database.addressStorage(keccak256(abi.encodePacked('billsplittingPayer', _billID, i))) == msg.sender ){
        emit LogAddressChanged(msg.sender, _newAddress);
        database.setAddress(keccak256(abi.encodePacked('billsplittingPayer', _billID, i)), _newAddress);
        uint owing = database.uintStorage(keccak256(abi.encodePacked('billsplittingOwing', _billID, msg.sender)));
        database.setUint(keccak256(abi.encodePacked('billsplittingOwing', _billID, _newAddress)), owing);
        database.setUint(keccak256(abi.encodePacked('billsplittingOwing', _billID, msg.sender)), 0);
      }
    }
  }
  //function changeReceiver()
  //function getUsersOwing()

  //function cancelBill()

  event LogNewBill(bytes32 _billID, address _receiver, uint _total);
  event LogAddressChanged(address _oldAddress, address _newAddress);
  event LogAddress(address _address);
}
