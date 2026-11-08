import { localCompletion } from '../../../frontend/server/local-llm';
import { writeFileSync } from 'node:fs';
async function main() {
  const start = Date.now();
  try {
    const result = await localCompletion({
      messages: [{ role: 'user', content: 'Return only JSON with keys task="compare_tools" and candidates=6.' }],
      response_format: { type: 'json_object' }, temperature: 0, max_tokens: 128,
    });
    const content = JSON.parse(result.choices[0].message.content);
    const evidence = { passed: content.task === 'compare_tools' && content.candidates === 6,
      seconds: (Date.now() - start) / 1000, content, usage: result.usage, scope: 'Actual BioMate localCompletion transport over SSH to Spark; synthetic JSON request.' };
    writeFileSync(new URL('./results/spark_qwen35_27b/biomate_transport.json', import.meta.url), JSON.stringify(evidence, null, 2));
    console.log(JSON.stringify(evidence));
  } catch (error) { console.error(String(error)); process.exitCode = 1; }
}
main();
