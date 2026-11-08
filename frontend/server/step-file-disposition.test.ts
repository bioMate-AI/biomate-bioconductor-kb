import {describe,it,expect} from 'vitest';
import {stepFileDisposition} from './step-file-disposition';
describe('authorized step-file response disposition',()=>{
 it('forces attachment only for explicit download=1, leaving normal preview inline',()=>{
  expect(stepFileDisposition('plot.png','1')).toMatch(/^attachment;/);
  for(const flag of [undefined,'0','true',['1']])expect(stepFileDisposition('plot.png',flag)).toMatch(/^inline;/);
 });
 it('safely encodes unicode and strips paths/control characters/header delimiters',()=>{
  const header=stepFileDisposition('/run/报告"\r\n.png','1');
  expect(header).not.toMatch(/[\r\n]/);expect(header).not.toContain('/run/');
  expect(header).toContain("filename*=UTF-8''%E6%8A%A5%E5%91%8A%22.png");
 });
});
