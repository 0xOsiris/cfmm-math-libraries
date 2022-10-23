// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

interface ScriptRunnerCheatCodes {
    function ffi(string[] calldata) external returns (bytes memory);
}

contract ScriptRunner {
    address constant HEVM_ADDRESS =
        address(bytes20(uint160(uint256(keccak256("hevm cheat code")))));

    ScriptRunnerCheatCodes cheatCodes = ScriptRunnerCheatCodes(HEVM_ADDRESS);

    function runPythonScript(string memory fileName)
        public
        returns (bytes memory)
    {
        string[] memory cmds = new string[](2);
        cmds[0] = "python3";
        cmds[1] = string.concat("scripts/", fileName, ".py");

        bytes memory bytecode = cheatCodes.ffi(cmds);

        return bytecode;
    }

    function runPythonScript(string memory path, string memory args)
        public
        returns (bytes memory)
    {
        string[] memory cmds = new string[](3);
        cmds[0] = "python3";
        cmds[1] = path;
        cmds[2] = args;

        bytes memory bytecode = cheatCodes.ffi(cmds);

        return bytecode;
    }

    function runPythonScript(string memory path, string[] memory args)
        public
        returns (bytes memory)
    {
        string[] memory cmds = new string[](5);
        cmds[0] = "python3";
        cmds[1] = path;
        cmds[2] = args[0];
        cmds[3] = args[1];
        cmds[4] = args[2];
        bytes memory bytecode = cheatCodes.ffi(cmds);

        return bytecode;
    }

    function runGoScript(string memory fileName)
        public
        returns (bytes memory)
    {
        string[] memory cmds = new string[](2);
        cmds[0] = "go";
        cmds[1] = string.concat("scripts/", fileName, ".py");

        bytes memory bytecode = cheatCodes.ffi(cmds);

        return bytecode;
    }

    function runGoScript(string memory fileName, string memory args)
        public
        returns (bytes memory)
    {
        string[] memory cmds = new string[](3);
        cmds[0] = "go";
        cmds[1] = string.concat("scripts/", fileName, ".go");
        cmds[2] = args;

        bytes memory bytecode = cheatCodes.ffi(cmds);

        return bytecode;
    }
}
