I checked the output, seen many details, and have plenty of questions: 0.
  First of all, are all the tests are controlled, instead of directly using
  biomate? 1. Necessary clarification question: when user asks "perform variant
  calling on whole gemone sequencing data using bwa and gatk", why the
  workflow is directly generated for the germline variant, without specific
  information confirmation from the user? 2. Information flow: when user is
  asking for a workflow execution, the first thing should be to check if the
  datasets specified, right? If no dataset provided, then it should not proceed
  with details of workflows. Besides, the format, size and other properties of
  the dataset will influence the workflow generation. For example, it may need
  a pilot study on a small amount of data first. If the datasets can not be
  accessed, then it is pointless to generate a workflow. 3. Is there a pre-set
  section structure of the workflow description, and the workflow panel? Will
  it be inconsistent dramatically when asked multiple times of the same query?
  4. It is already clearly forbidden that a stupid long list of qc profile
  present at the front fo the user to choose, which should be an automated work
  of biomate itself, why it is still shown in the workflow panel? The current
  QC Setting is only confusing and useless. How do the user know the metric_key
  and value range/unit? Don't the biomate decide and provide explicitly? Most
  importantly, are you sure it is the latest biomate panel? I see another panel
  view from another colleague already. 5. Moreover, showing a long list of
  scientific rational of when to use and do not use when, plus a list of
  recommended prarameters descriptions are also overwhelming to users and
  unnecessary, which should be used by biomate, and should only be provided if
  any specific piece of scientic rational is applied in the current task and
  the user should be provided with a brief rational. 6. Some of the workflow
  descriptions show the section of tools in use, the information provided is
  not informative to users, with a backend workflow path and general name. For
  example, for the cryo SPA workflow, the tool used is the cryoSPARC, and the
  fallback is RELION. Too many useless text is in the "Tools in Use". 7. check
  the demo-recordings in  /home/yzhang/biomate/demo-recordings/. The panel
  format is more preferrable in this folder. Why it is different from your
  screenshots? 8. In the  /home/yzhang/biomate/demo-recordings/ screenshots,
  there is a section of "nextsteps after this workflow", remove it from the
  workflow description response. Once the workflow execution is finished,
  biomate can suggest next steps. However, for cryosparc workflows, are you
  sure all the next steps recommended in are already well-prepared workflows
  tested soundly? 8. Can the left chat history panel be hidden automatically
  when the workflow panel is shown at the right view. It is too crowd. 9. Why
  it is always stopped at "awaiting for review"? I want e2e test with workflow
  execution, so that to check the progress log, the resume, pause... button
  functions, and the function of step by step workflow execution. Also the
  output visulization and other manipulations. 