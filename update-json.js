const fs = require("fs");
const file = process.argv[2];
const target = process.argv[3];
const data = fs.readFileSync(file, "utf-8");
const json = JSON.parse(data);

delete json.bytecode;
delete json.deployedBytecode;
delete json.linkReferences;
delete json.deployedLinkReferences;

fs.writeFileSync(target, JSON.stringify(json, null, 2), "utf-8");
