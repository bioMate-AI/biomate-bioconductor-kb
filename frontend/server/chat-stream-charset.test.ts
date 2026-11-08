import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import ts from 'typescript';
import { describe, expect, it } from 'vitest';

// Wiring guard for BOTH the normal stream and the safety-refusal stream.
// Chrome's captured response text otherwise defaults to a legacy charset,
// corrupting mathematical minus, micro units and Chinese in API consumers.
describe('chat stream response encoding', () => {
  it('declares UTF-8 on every chat-stream content-type branch', () => {
    const source = ts.createSourceFile('routes.ts', readFileSync(resolve(__dirname, 'routes.ts'), 'utf8'),
      ts.ScriptTarget.Latest, true);
    const types: string[] = [];
    let routes = 0;
    function collect(node: ts.Node) {
      if (ts.isCallExpression(node) && ts.isPropertyAccessExpression(node.expression)
        && node.expression.name.text === 'setHeader'
        && node.arguments[0] && ts.isStringLiteral(node.arguments[0])
        && node.arguments[0].text.toLowerCase() === 'content-type') {
        const value = node.arguments[1];
        types.push(value && ts.isStringLiteral(value) ? value.text : '<nonliteral>');
      }
      ts.forEachChild(node, collect);
    }
    function visit(node: ts.Node) {
      if (ts.isCallExpression(node) && ts.isPropertyAccessExpression(node.expression)
        && node.expression.name.text === 'post' && node.arguments[0]
        && ts.isStringLiteral(node.arguments[0]) && node.arguments[0].text === '/api/chat/stream') {
        routes++;
        node.arguments.slice(1).forEach(collect);
      } else ts.forEachChild(node, visit);
    }
    visit(source);
    expect(routes).toBe(1);
    expect(types).toEqual(['text/event-stream; charset=utf-8', 'text/event-stream; charset=utf-8']);
  });
});
