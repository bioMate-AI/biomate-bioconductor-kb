/* Enhance long articles without making their content dependent on JavaScript. */
(function () {
  var article = document.querySelector('article.bm-prose, .article-body');
  if (!article || document.querySelector('.ed-survey')) return;
  article.classList.add('ed-blog-article');
  var headings = Array.from(article.querySelectorAll('h2'));
  if (headings.length >= 3) {
    var nav = document.createElement('nav');
    nav.className = 'ed-blog-nav';
    nav.setAttribute('aria-label', 'In this article');
    var title = document.createElement('p');
    title.textContent = 'In this article';
    nav.appendChild(title);
    var list = document.createElement('ol');
    headings.forEach(function (heading, index) {
      if (!heading.id) {
        var candidate = 'article-section-' + (index + 1);
        while (document.getElementById(candidate)) candidate += '-next';
        heading.id = candidate;
      }
      var item = document.createElement('li');
      var link = document.createElement('a');
      link.href = '#' + heading.id;
      link.textContent = heading.textContent;
      item.appendChild(link);
      list.appendChild(item);
    });
    nav.appendChild(list);
    var lead = article.querySelector('p');
    if (lead && lead.parentElement === article) lead.after(nav);
    else article.prepend(nav);
  }
  article.querySelectorAll('table').forEach(function (table) {
    var wrapper = document.createElement('div');
    wrapper.className = 'ed-blog-table';
    wrapper.tabIndex = 0;
    wrapper.setAttribute('role', 'region');
    wrapper.setAttribute('aria-label', 'Scrollable article table');
    table.replaceWith(wrapper);
    wrapper.appendChild(table);
  });
})();
