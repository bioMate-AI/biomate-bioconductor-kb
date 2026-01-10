1. UI: automatically generate interface for parameter selection, can be step by step, or overall. Depends on the complexity of the task. Some tools or tasks may be very straightforward. Some are more experimental, if there are parameters need to be tuned, ask the user about the preference. For nextflow workflows, they are integrating multiple paths into the same workflow, which can be specified from the very beginning. 
2. Workflow save and reuse: the workflows should find a place so that the user can reuse them in future. It should be able to support parameter changes directly in a UI.
3. At least the UI should be able to replicate galaxy ability for the entire work
4. Adding clinical opensource pipelines, so that the biological output can be directly put together with the clinical models
5. Add audio communication
6.Check the completeness of docker tools
7. For the latest models/tools/datasets, blog them, mining out best pratice and benchmark
8. What is the typical workflow: preprocessing data - computation - visulization and conclusion, conclusion is important. QC is also important. Make early stop for user confirmation before continuing on the entire computation if exceptional output found. That means each step should be examined and get some conclusion. 
10. For parameter tuning, may not need to use the entire dataset if too large, can use a fraction based on the user's choice. 
11. Start from MIMIC for clinical data process, extend to others later
12. Group using the same project

