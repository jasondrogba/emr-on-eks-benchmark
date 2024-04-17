

select /* TPC-DS query8.tpl 0.63 */  s_store_name
     ,sum(ss_net_profit)
from store_sales
   ,date_dim
   ,store,
    (select ca_zip
     from (
              SELECT substr(ca_zip,1,5) ca_zip
              FROM customer_address
              WHERE substr(ca_zip,1,5) IN (
                                           '26556','82112','24494','73691','98508','18363',
                                           '41721','46255','78664','37879','34631',
                                           '17403','95906','94421','28597','65967',
                                           '69188','51636','36103','45863','80231',
                                           '79103','41954','15519','61556','60058',
                                           '48509','37205','10650','59740','59298',
                                           '13874','56012','65512','52264','54461',
                                           '59470','14637','10372','67783','97087',
                                           '62039','40518','60351','38632','19606',
                                           '80070','59580','86492','55927','64327',
                                           '53882','67474','12458','82078','46252',
                                           '49165','13401','18594','65541','68465',
                                           '97735','24310','68631','48690','39042',
                                           '90155','82017','47883','11086','82378',
                                           '10370','28527','29801','15250','41710',
                                           '61843','72074','86421','46740','53095',
                                           '66122','49141','72860','76856','42354',
                                           '73478','23432','38411','68186','22463',
                                           '79797','33813','43372','13791','10809',
                                           '65618','12450','76873','49396','85237',
                                           '26488','57775','31180','18716','81011',
                                           '83681','66000','11771','73015','33835',
                                           '46817','76701','31547','83457','75436',
                                           '56571','43139','10402','12697','97655',
                                           '26816','48020','51327','66247','19638',
                                           '27924','56952','98110','32832','45822',
                                           '40701','42224','61006','84718','56193',
                                           '73599','16391','58743','57732','91680',
                                           '30943','32250','66700','43635','31814',
                                           '36844','31473','65152','57290','95503',
                                           '19135','24537','31616','76138','25098',
                                           '61834','25575','17242','42476','14038',
                                           '45935','46640','32629','78679','15184',
                                           '58733','29653','35033','91955','55438',
                                           '59385','51260','94033','93405','35163',
                                           '88445','43583','25436','26866','21031',
                                           '92837','35145','24525','23420','88229',
                                           '76177','44450','13151','36177','55985',
                                           '79267','48952','82431','47695','40498',
                                           '25822','58483','45280','28927','56469',
                                           '83913','68230','10239','68388','29779',
                                           '43154','19312','61069','87600','10954',
                                           '13819','48918','58684','47648','91715',
                                           '22597','37040','68547','84107','79889',
                                           '88543','60666','58974','19022','48431',
                                           '22189','86395','37827','56350','86895',
                                           '99043','68580','65360','27802','80243',
                                           '76348','45282','10256','17332','60662',
                                           '69071','73700','17112','31443','50184',
                                           '77431','19501','57676','73777','46583',
                                           '20964','25007','73595','68097','47714',
                                           '88677','65600','26205','34419','86714',
                                           '48988','62918','69497','68714','81334',
                                           '73065','13377','74375','90645','65230',
                                           '89804','83041','47768','74883','64661',
                                           '81274','71543','34286','71187','67840',
                                           '33566','14169','72824','91239','32800',
                                           '96800','11912','20618','65860','21770',
                                           '10639','54057','27720','41069','23249',
                                           '26538','35337','49769','25421','56853',
                                           '21054','63991','91130','54032','72754',
                                           '18837','88940','40610','96229','72583',
                                           '91490','85543','58228','19319','79825',
                                           '42284','38667','42295','50270','77379',
                                           '34373','48957','61684','99140','72081',
                                           '23102','93733','48243','94248','73453',
                                           '29850','81312','37403','62464','22310',
                                           '72204','66646','28100','21010','25273',
                                           '31969','65294','77042','51049','68577',
                                           '20466','19183','14641','52685','86569',
                                           '88149','40016','67759','82318','23271',
                                           '17105','20084','19551','32376','57892',
                                           '24874','64449','15345','76044','93800',
                                           '79979','97579','20209','64988','12896',
                                           '31940','21327','67892','72990','56774',
                                           '68787','52096','74943','18423','78791',
                                           '75359','73805','24386','33058','79698',
                                           '35405','44431','94433','17701','93876',
                                           '16520','91611','95666','50200','13262',
                                           '25443','51576','29248','29727')
              intersect
              select ca_zip
              from (SELECT substr(ca_zip,1,5) ca_zip,count(*) cnt
                    FROM customer_address, customer
                    WHERE ca_address_sk = c_current_addr_sk and
                            c_preferred_cust_flag='Y'
                    group by ca_zip
                    having count(*) > 10)A1)A2) V1
where ss_store_sk = s_store_sk
  and ss_sold_date_sk = d_date_sk
  and d_qoy = 2 and d_year = 2000
  and (substr(s_zip,1,2) = substr(V1.ca_zip,1,2))
group by s_store_name
order by s_store_name
    limit 100
