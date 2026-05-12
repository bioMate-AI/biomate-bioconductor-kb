// Asset type declarations for image imports
declare module '@assets/generated_images/*.png' {
  const content: string;
  export default content;
}

declare module '@assets/generated_images/*.jpg' {
  const content: string;
  export default content;
}

declare module '@assets/generated_images/*.svg' {
  const content: string;
  export default content;
}

declare module '@assets/*.png' {
  const content: string;
  export default content;
}

declare module '@assets/*.jpg' {
  const content: string;
  export default content;
}

declare module '@assets/*.svg' {
  const content: string;
  export default content;
}

// Generic image imports
declare module '*.png' {
  const content: string;
  export default content;
}

declare module '*.jpg' {
  const content: string;
  export default content;
}

declare module '*.jpeg' {
  const content: string;
  export default content;
}

declare module '*.svg' {
  const content: string;
  export default content;
}

declare module '*.gif' {
  const content: string;
  export default content;
}

// Vite ?raw imports — load file contents as a string at build time
declare module '*?raw' {
  const content: string;
  export default content;
}

declare module '*.md' {
  const content: string;
  export default content;
}
