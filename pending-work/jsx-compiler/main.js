const fs = require('fs');

const output = require("@babel/core").transformSync(fs.readFileSync("program.jsx", { encoding: 'utf8'}), {
    plugins: ["@babel/plugin-transform-react-jsx"],
}).code;

fs.writeFileSync('output.js', output, { encoding: 'utf8' });
