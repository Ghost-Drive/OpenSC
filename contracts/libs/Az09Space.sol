pragma solidity 0.8.9;

library Az09Space {
  struct State {
    bool accepts;
    function (bytes1) pure internal returns (State memory) func;
  }

  string public constant regex = "[A-Za-z0-9][A-Za-z0-9 \\-]*[A-Za-z0-9]|[A-Za-z0-9]";

  function s0(bytes1 c) pure internal returns (State memory) {
    c = c;
    return State(false, s0);
  }

  function s1(bytes1 c_) pure internal returns (State memory) {
    uint c = uint(uint8(c_));
    if (c >= 48 && c <= 57 || c >= 65 && c <= 90 || c >= 97 && c <= 122) {
      return State(true, s2);
    }

    return State(false, s0);
  }

  function s2(bytes1 c_) pure internal returns (State memory) {
    uint c = uint(uint8(c_));
    if (c == 32 || c == 45) {
      return State(false, s3);
    }
    if (c >= 48 && c <= 57 || c >= 65 && c <= 90 || c >= 97 && c <= 122) {
      return State(true, s4);
    }

    return State(false, s0);
  }

  function s3(bytes1 c_) pure internal returns (State memory) {
    uint c = uint(uint8(c_));
    if (c == 32 || c == 45) {
      return State(false, s3);
    }
    if (c >= 48 && c <= 57 || c >= 65 && c <= 90 || c >= 97 && c <= 122) {
      return State(true, s4);
    }

    return State(false, s0);
  }

  function s4(bytes1 c_) pure internal returns (State memory) {
    uint c = uint(uint8(c_));
    if (c == 32 || c == 45) {
      return State(false, s3);
    }
    if (c >= 48 && c <= 57 || c >= 65 && c <= 90 || c >= 97 && c <= 122) {
      return State(true, s4);
    }

    return State(false, s0);
  }

  function isAZ09Space(string calldata input) public pure returns (bool) {
    State memory cur = State(false, s1);

    for (uint i = 0; i < bytes(input).length; i++) {
      bytes1 c = bytes(input)[i];

      cur = cur.func(c);
    }

    return cur.accepts;
  }
}
