import { describe, expect, it } from "vitest";
import {
  applyPreparedInputParamsToWorkflow,
  parsePreparedInputParams,
} from "./prepared-inputs-params";

describe("parsePreparedInputParams", () => {
  it("reads movies_path from the Prepared inputs block", () => {
    const msg =
      "Process this cryo-EM dataset.\n" +
      "[Prepared inputs: Set movies_path=s3://biomate-cryo-data/empiar-10028/Micrographs/. pixel size 0.885]";
    expect(parsePreparedInputParams(msg, ["movies_path", "pixel_size"])).toEqual({
      movies_path: "s3://biomate-cryo-data/empiar-10028/Micrographs/",
    });
  });

  it("reads analysis=screening for crisprseq", () => {
    const msg =
      "[Prepared inputs: Set analysis=screening. Bind count_table to ht29_minlibcas9_counts.tsv]";
    expect(parsePreparedInputParams(msg, ["analysis", "count_table"])).toEqual({
      analysis: "screening",
    });
  });

  it("reads ligand_a / ligand_b / receptor for openfe_rbfe", () => {
    const msg =
      "[Prepared inputs: set receptor=1IEP.pdb, ligand_a=imatinib.sdf, ligand_b=dasatinib.sdf]";
    expect(
      parsePreparedInputParams(msg, ["receptor", "ligand_a", "ligand_b", "outdir"]),
    ).toEqual({
      receptor: "1IEP.pdb",
      ligand_a: "imatinib.sdf",
      ligand_b: "dasatinib.sdf",
    });
  });

  it("supports quoted values with spaces", () => {
    const msg = '[Prepared inputs: pulldown_sample="LFQ intensity H1"]';
    expect(parsePreparedInputParams(msg, ["pulldown_sample"])).toEqual({
      pulldown_sample: "LFQ intensity H1",
    });
  });

  it("ignores keys not in the schema allow-list", () => {
    const msg = "[Prepared inputs: movies_path=s3://x/ movies_fake=y]";
    expect(parsePreparedInputParams(msg, ["movies_path"])).toEqual({
      movies_path: "s3://x/",
    });
  });
});

describe("applyPreparedInputParamsToWorkflow", () => {
  it("fills empty required_params and inline_parameters without overwriting", () => {
    const ga: any = {
      required_params: [
        { name: "movies_path", value: null, required: true },
        { name: "analysis", value: "targeted", required: true },
      ],
      optional_params: [],
    };
    const seeded = applyPreparedInputParamsToWorkflow(
      ga,
      "[Prepared inputs: movies_path=s3://biomate-cryo-data/empiar-10028/Micrographs/ analysis=screening]",
    );
    expect(seeded).toEqual(["movies_path"]);
    expect(ga.required_params[0].value).toBe(
      "s3://biomate-cryo-data/empiar-10028/Micrographs/",
    );
    expect(ga.required_params[0].autoFilled).toBe(true);
    expect(ga.required_params[1].value).toBe("targeted"); // not overwritten
    expect(ga.inline_parameters.movies_path).toBe(
      "s3://biomate-cryo-data/empiar-10028/Micrographs/",
    );
  });
});
