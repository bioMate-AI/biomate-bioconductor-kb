// Read-only source extraction. Does not import or execute BioMate application code.
const fs = require('fs');
const path = require('path');
const cp = require('child_process');
const crypto = require('crypto');
const root = path.resolve(__dirname, '../..');
const ts = require(path.join(root, 'frontend/node_modules/typescript'));
const files = cp.execFileSync('git', ['ls-files', 'frontend/server'], {cwd: root, encoding:'utf8'}).trim().split('\n');
const records = [];
for (const file of files) {
  if (!file.endsWith('.ts') || /test|prototype/.test(file)) continue;
  const source = fs.readFileSync(path.join(root,file), 'utf8');
  const sf = ts.createSourceFile(file, source, ts.ScriptTarget.Latest, true);
  function visit(node) {
    let label, value;
    if ((ts.isVariableDeclaration(node) || ts.isPropertyDeclaration(node)) && node.initializer) {
      label = node.name.getText(sf); value = node.initializer;
      if (!/prompt|^system$|^SYSTEM$|^userContent$|^user$/i.test(label)) value = null;
    } else if (ts.isPropertyAssignment(node) && /^(system|systemInstruction)$/.test(node.name.getText(sf))) {
      label = node.name.getText(sf); value = node.initializer;
    } else if (ts.isBinaryExpression(node) && node.operatorToken.kind === ts.SyntaxKind.EqualsToken && /prompt|^SYSTEM$|^system$/i.test(node.left.getText(sf))) {
      label = node.left.getText(sf); value = node.right;
    } else if ((ts.isFunctionDeclaration(node) || ts.isMethodDeclaration(node)) && node.name && /(?:build.*(?:prompt|system)|.*prompt$)/i.test(node.name.getText(sf))) {
      label = 'builder:' + node.name.getText(sf); value = node;
    }
    if (value && value.getText(sf).length > 35) {
      const expression = value.getText(sf);
      const start = sf.getLineAndCharacterOfPosition(value.getStart(sf)).line + 1;
      const end = sf.getLineAndCharacterOfPosition(value.end).line + 1;
      records.push({file, start, end, label, language:'typescript', source_expression:expression,
        source_file_sha256:crypto.createHash('sha256').update(source).digest('hex')});
    }
    ts.forEachChild(node, visit);
  }
  visit(sf);
}
process.stdout.write(JSON.stringify(records));
