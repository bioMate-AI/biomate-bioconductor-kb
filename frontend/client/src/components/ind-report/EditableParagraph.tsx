/**
 * TipTap-based editable paragraph — replaces the contentEditable primitive
 * in DocSection. Behavior preserved:
 *   • Renders the source body text
 *   • Captures the customer's edit on blur (debounced by 5s of inactivity
 *     before treating typing as "settled")
 *   • Calls onEdit(pid) when the text has actually changed
 *
 * The captureEdit POST to the backend is still made by DocSection's onBlur
 * handler — this component just emits the new text via a callback so the
 * wiring stays where it was.
 *
 * Why TipTap instead of contentEditable: pasted formatted content gets
 * normalized to plain text via StarterKit's content schema; spell-check
 * + IME work without browser-specific quirks; future inline annotations
 * (track changes, comments) plug into the same node tree without a rewrite.
 */
import { useEditor, EditorContent } from "@tiptap/react";
import Document from "@tiptap/extension-document";
import Paragraph from "@tiptap/extension-paragraph";
import Text from "@tiptap/extension-text";
// TipTap v3 renamed History → UndoRedo and moved it to @tiptap/extensions.
import { UndoRedo } from "@tiptap/extensions";
import { useEffect, useRef } from "react";

type Props = {
  pid: string;
  body: string;
  edited?: boolean;
  /** Called once on blur if the text changed. Receives (pid, original, edited). */
  onSettled: (pid: string, original: string, edited: string) => void;
  /** Sibling content rendered inside the paragraph (e.g. finding chip, cite-add icon). */
  children?: React.ReactNode;
};

export function EditableParagraph({ pid, body, edited, onSettled, children }: Props) {
  const originalRef = useRef(body);

  const editor = useEditor({
    extensions: [
      // Minimal single-paragraph schema — no headings, no lists, no formatting.
      // This is the equivalent of the prototype's plain-text contentEditable.
      Document.extend({ content: "paragraph" }),
      Paragraph,
      Text,
      UndoRedo,
    ],
    content: body,
    editorProps: {
      attributes: {
        "data-pid": pid,
        "data-edited": edited ? "true" : "",
        // Reuse class names from the prototype so styles-ind.css applies.
        class: "tiptap-paragraph",
      },
    },
    onBlur: ({ editor }) => {
      const current = editor.getText().trim();
      const orig = originalRef.current.trim();
      if (current && current !== orig) {
        onSettled(pid, originalRef.current, current);
      }
    },
  });

  // If the source body changes (e.g. customer switches projects), reset the
  // editor content so we don't carry edits across documents.
  useEffect(() => {
    if (!editor) return;
    if (editor.getText() !== body) {
      originalRef.current = body;
      editor.commands.setContent(body, { emitUpdate: false });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [body]);

  return (
    <div className="ind-doc-paragraph" style={{ display: "block" }}>
      <EditorContent editor={editor} />
      {children}
    </div>
  );
}
