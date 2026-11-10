-- S10. Rendimiento en kg por hectárea de cada parcela y campaña, e identificación
-- de las parcelas que rinden menos que el promedio de su finca.
-- CTE + subconsulta correlacionada sobre lote (900) y parcela (600).
WITH rendimiento AS (
    SELECT p.id_finca,
           l.numero_parcela,
           l.campaña,
           SUM(l.kg_cosecha) / NULLIF(p.superficie, 0) AS kg_ha
    FROM lote l
    JOIN parcela p
      ON p.id_finca = l.id_finca
     AND p.numero_parcela = l.numero_parcela
    GROUP BY p.id_finca, l.numero_parcela, l.campaña, p.superficie
)
SELECT r.id_finca,
       r.numero_parcela,
       r.campaña,
       ROUND(r.kg_ha, 2) AS kg_ha
FROM rendimiento r
WHERE r.kg_ha < (
        SELECT AVG(r2.kg_ha)
        FROM rendimiento r2
        WHERE r2.id_finca = r.id_finca
      )
ORDER BY r.id_finca, r.campaña, r.numero_parcela;
